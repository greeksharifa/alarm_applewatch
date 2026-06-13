#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${ROOT_DIR}/alarm_applewatch.xcodeproj"
PBXPROJ="${PROJECT}/project.pbxproj"
SCHEME="alarm_applewatch Watch App"
WATCH_ENTITLEMENTS="${ROOT_DIR}/alarm_applewatch Watch App/alarm_applewatch_Watch_App.entitlements"
DEVICE_CHECK_DERIVED_DATA="${ROOT_DIR}/.build/DerivedData-RealDeviceCheck"

status=0

section() {
  printf '\n== %s ==\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1" >&2
  status=1
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    warn "Missing required tool: $1"
  fi
}

section "Required Tools"
require_tool xcodebuild
require_tool xcrun
require_tool plutil
require_tool system_profiler
require_tool ioreg
require_tool python3

section "Xcode"
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version || warn "xcodebuild -version failed"
else
  warn "xcodebuild is unavailable"
fi

section "Project Scheme"
if [[ -d "${PROJECT}" ]]; then
  if xcodebuild -list -project "${PROJECT}" 2>&1 | sed -n '/Information about project/,$p'; then
    :
  else
    warn "Could not list Xcode project schemes"
  fi
else
  warn "Missing project: ${PROJECT}"
fi

section "Watch Target Settings"
if [[ -f "${PBXPROJ}" ]]; then
  grep -E 'PRODUCT_BUNDLE_IDENTIFIER|WATCHOS_DEPLOYMENT_TARGET|DEVELOPMENT_TEAM|CODE_SIGN_ENTITLEMENTS|INFOPLIST_FILE' "${PBXPROJ}" \
    | sed 's/^[[:space:]]*//'
else
  warn "Missing project file: ${PBXPROJ}"
fi

section "Watch Entitlements"
if [[ -f "${WATCH_ENTITLEMENTS}" ]]; then
  plutil -p "${WATCH_ENTITLEMENTS}" || warn "Could not parse Watch entitlements"
else
  warn "Missing Watch entitlements file: ${WATCH_ENTITLEMENTS}"
fi

section "USB Device Inventory"
usb_seen=0
if command -v system_profiler >/dev/null 2>&1; then
  system_usb_output="$(system_profiler SPUSBDataType -json 2>&1)"
  system_usb_status=$?
  printf '%s\n' "${system_usb_output}"

  if [[ ${system_usb_status} -ne 0 ]]; then
    warn "system_profiler could not inspect USB devices."
  elif printf '%s\n' "${system_usb_output}" | grep -Eiq 'iPhone|iPad|iPod'; then
    usb_seen=1
  fi
else
  warn "system_profiler is unavailable"
fi

if command -v ioreg >/dev/null 2>&1; then
  ioreg_usb_output="$(
    ioreg -p IOUSB -l -w0 2>&1 \
      | awk '/[+]-o .*iPhone|[+]-o .*iPad|[+]-o .*iPod/ { remaining = 45 } remaining > 0 { print; remaining-- }'
  )"
  printf '%s\n' "${ioreg_usb_output}"

  if printf '%s\n' "${ioreg_usb_output}" | grep -Eiq 'iPhone|iPad|iPod|SupportsIPhoneOS'; then
    usb_seen=1
  fi
else
  warn "ioreg is unavailable"
fi

if [[ ${usb_seen} -eq 0 ]]; then
  warn "No USB-connected iPhone/iPad is visible. Xcode normally reaches Apple Watch through the paired iPhone."
fi

section "usbmuxd and lockdownd"
primary_udid=""
if command -v python3 >/dev/null 2>&1; then
  lockdownd_output="$(
    python3 - <<'PY'
import plistlib
import socket
import struct
import sys

USBMUX = "/var/run/usbmuxd"

def usbmux_roundtrip(message):
    payload = plistlib.dumps(message, fmt=plistlib.FMT_XML)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(USBMUX)
    sock.sendall(struct.pack("IIII", 16 + len(payload), 1, 8, 1) + payload)
    header = sock.recv(16)
    if len(header) != 16:
        raise RuntimeError("short usbmuxd response")
    length, _version, _message_type, _tag = struct.unpack("IIII", header)
    data = b""
    while len(data) < length - 16:
        chunk = sock.recv(length - 16 - len(data))
        if not chunk:
            break
        data += chunk
    return sock, plistlib.loads(data)

def lockdown_send(sock, message):
    payload = plistlib.dumps(message, fmt=plistlib.FMT_XML)
    sock.sendall(struct.pack(">I", len(payload)) + payload)
    header = sock.recv(4)
    if len(header) != 4:
        raise RuntimeError("short lockdownd response")
    length = struct.unpack(">I", header)[0]
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            break
        data += chunk
    return plistlib.loads(data)

sock, devices = usbmux_roundtrip({
    "MessageType": "ListDevices",
    "ClientVersionString": "wakeguard-check",
    "ProgName": "wakeguard-check",
    "kLibUSBMuxVersion": 3,
})
sock.close()
device_list = devices.get("DeviceList", [])
print(f"usbmuxd devices: {len(device_list)}")
if not device_list:
    sys.exit(1)

properties = device_list[0].get("Properties", {})
print(f"usbmuxd first device: {properties.get('SerialNumber')} via {properties.get('ConnectionType')}")
device_id = properties["DeviceID"]
sock, response = usbmux_roundtrip({
    "MessageType": "Connect",
    "ClientVersionString": "wakeguard-check",
    "ProgName": "wakeguard-check",
    "DeviceID": device_id,
    "PortNumber": socket.htons(62078),
})
if response.get("Number") != 0:
    print(f"lockdownd connect failed: {response}")
    sys.exit(1)

for key in ("DeviceName", "ProductVersion", "ProductType", "UniqueDeviceID"):
    value = lockdown_send(sock, {"Label": "wakeguard-check", "Request": "GetValue", "Key": key})
    print(f"lockdownd {key}: {value.get('Value', value.get('Error'))}")
PY
  )"
  lockdownd_status=$?
  printf '%s\n' "${lockdownd_output}"
  primary_udid="$(printf '%s\n' "${lockdownd_output}" | sed -n 's/^lockdownd UniqueDeviceID: //p' | head -1)"
  if [[ ${lockdownd_status} -ne 0 ]]; then
    warn "usbmuxd/lockdownd check failed."
  fi
else
  warn "python3 is unavailable"
fi

if [[ -n "${primary_udid}" ]] && command -v xcrun >/dev/null 2>&1; then
  section "Xcode USB Attach Wait"
  xcdevice_wait_output="$(xcrun xcdevice wait --usb --timeout=20 "${primary_udid}" 2>&1)"
  xcdevice_wait_status=$?
  printf '%s\n' "${xcdevice_wait_output}"
  if [[ ${xcdevice_wait_status} -ne 0 ]]; then
    warn "xcdevice did not observe the primary iPhone over USB."
  fi
fi

section "CoreDevice Device List"
if command -v xcrun >/dev/null 2>&1; then
  device_output="$(xcrun devicectl list devices 2>&1)"
  device_status=$?
  printf '%s\n' "${device_output}"

  if [[ ${device_status} -ne 0 ]]; then
    warn "devicectl could not list devices. Open Xcode, unlock iPhone/Watch, reconnect USB, and retry."
  elif printf '%s\n' "${device_output}" | grep -q 'No devices found'; then
    warn "No physical iPhone/Apple Watch is currently visible to Xcode/CoreDevice."
  elif ! printf '%s\n' "${device_output}" | grep -Eiq 'watch|iphone'; then
    warn "devicectl returned devices, but no obvious iPhone/Apple Watch entry was detected."
  fi
else
  warn "xcrun is unavailable"
fi

section "Xcode Device List"
if command -v xcrun >/dev/null 2>&1; then
  xcdevice_output="$(xcrun xcdevice list 2>&1)"
  xcdevice_status=$?
  printf '%s\n' "${xcdevice_output}"

  if [[ ${xcdevice_status} -ne 0 ]]; then
    warn "xcdevice could not list devices."
  elif ! printf '%s\n' "${xcdevice_output}" | grep -Eiq 'watch|iphone'; then
    warn "xcdevice does not show a physical iPhone or Apple Watch."
  fi
else
  warn "xcrun is unavailable"
fi

section "Xcode Instruments Devices"
if command -v xcrun >/dev/null 2>&1; then
  xctrace_output="$(xcrun xctrace list devices 2>&1)"
  xctrace_status=$?
  printf '%s\n' "${xctrace_output}"

  if [[ ${xctrace_status} -ne 0 ]]; then
    warn "xctrace could not list devices."
  elif printf '%s\n' "${xctrace_output}" | grep -q 'No devices available'; then
    warn "xctrace reports no recording-capable devices."
  elif ! printf '%s\n' "${xctrace_output}" | grep -Eiq 'watch|iphone'; then
    warn "xctrace does not show a physical iPhone or Apple Watch."
  fi
else
  warn "xcrun is unavailable"
fi

section "Xcode Destinations"
if command -v xcodebuild >/dev/null 2>&1; then
  destination_output="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -showdestinations 2>&1)"
  destination_status=$?
  printf '%s\n' "${destination_output}"

  if [[ ${destination_status} -ne 0 ]]; then
    warn "xcodebuild could not show destinations for the Watch scheme."
  elif ! printf '%s\n' "${destination_output}" \
      | grep '{ platform:watchOS,' \
      | grep -v 'placeholder' \
      | grep -vq 'Simulator'; then
    warn "No physical Apple Watch destination is visible to Xcode for this scheme."
  fi
else
  warn "xcodebuild is unavailable"
fi

section "Signed Device Build Probe"
if command -v xcodebuild >/dev/null 2>&1; then
  build_log="$(mktemp -t wakeguard-device-build.XXXXXX.log)"
  if xcodebuild \
      -quiet \
      -allowProvisioningUpdates \
      -project "${PROJECT}" \
      -scheme "${SCHEME}" \
      -destination 'generic/platform=watchOS' \
      -derivedDataPath "${DEVICE_CHECK_DERIVED_DATA}" \
      build >"${build_log}" 2>&1; then
    printf 'Signed generic watchOS build passed.\n'
  else
    cat "${build_log}"
    warn "Signed generic watchOS build failed. Fix Xcode account, Team, registered devices, bundle IDs, or provisioning profiles before a real Watch run."
  fi
  rm -f "${build_log}"
else
  warn "xcodebuild is unavailable"
fi

section "Next Xcode Run"
cat <<EOF
1. Pair Apple Watch with iPhone in the iPhone Watch app.
2. Connect iPhone to Mac over USB and trust the Mac.
3. Enable Developer Mode on iPhone and Apple Watch.
4. In Xcode, select scheme "${SCHEME}".
5. Select the physical Apple Watch destination under the paired iPhone.
6. Press Cmd+R and grant HealthKit and notification permissions on first launch.
EOF

exit "${status}"
