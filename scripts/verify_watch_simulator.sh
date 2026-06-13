#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/.env"
  set +a
fi

: "${WATCH_UDID:?Set WATCH_UDID to a watchOS simulator UDID from xcrun simctl list devices.}"
WATCH_APP_BUNDLE_ID="${WATCH_APP_BUNDLE_ID:-dev.local.alarm-applewatch.watchkitapp}"
APP_ID="${WATCH_APP_BUNDLE_ID}"
DERIVED_DATA="${ROOT_DIR}/.build/DerivedData-VerifySim"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug-watchsimulator/alarm_applewatch Watch App.app"
LOG_FILE="${TMPDIR:-/tmp}/wakeguard-verify-sim.log"
PID_FILE="${TMPDIR:-/tmp}/wakeguard-verify-sim-log.pid"

cd "${ROOT_DIR}"

xcodebuild -quiet \
  -project alarm_applewatch.xcodeproj \
  -scheme "alarm_applewatch Watch App" \
  -destination "generic/platform=watchOS Simulator" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcrun simctl boot "${WATCH_UDID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${WATCH_UDID}" -b >/dev/null
xcrun simctl terminate "${WATCH_UDID}" "${APP_ID}" >/dev/null 2>&1 || true
xcrun simctl install "${WATCH_UDID}" "${APP_PATH}"

rm -f "${LOG_FILE}" "${PID_FILE}"
xcrun simctl spawn "${WATCH_UDID}" log stream \
  --style compact \
  --level info \
  --predicate "subsystem == \"${APP_ID}\"" \
  >"${LOG_FILE}" 2>&1 &
echo $! >"${PID_FILE}"

SIMCTL_CHILD_WAKE_GUARD_DIAGNOSTIC_MODE=1 \
  xcrun simctl launch --terminate-running-process "${WATCH_UDID}" "${APP_ID}" >/dev/null

sleep 75
kill "$(cat "${PID_FILE}")" >/dev/null 2>&1 || true

for phase in diagnostic-1 diagnostic-2 diagnostic-3; do
  if ! grep -q "phase started ${phase}" "${LOG_FILE}"; then
    echo "Missing phase start for ${phase}" >&2
    tail -n 160 "${LOG_FILE}" >&2
    exit 1
  fi

  if ! grep -q "phase ended ${phase}" "${LOG_FILE}"; then
    echo "Missing phase end for ${phase}" >&2
    tail -n 160 "${LOG_FILE}" >&2
    exit 1
  fi
done

if ! grep -q "haptic pulse phase=diagnostic-3 pulse=10" "${LOG_FILE}"; then
  echo "Missing expected tenth diagnostic pulse evidence" >&2
  tail -n 160 "${LOG_FILE}" >&2
  exit 1
fi

echo "Simulator diagnostic verification passed. Log: ${LOG_FILE}"
tail -n 80 "${LOG_FILE}"
