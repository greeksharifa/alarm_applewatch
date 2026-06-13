#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/.env"
  set +a
fi

: "${WATCH_DEVICE:?Set WATCH_DEVICE to the Apple Watch identifier from xcrun devicectl list devices.}"
: "${IOS_DESTINATION_ID:?Set IOS_DESTINATION_ID to the paired iPhone destination id for xcodebuild.}"
WATCH_APP_BUNDLE_ID="${WATCH_APP_BUNDLE_ID:-dev.local.alarm-applewatch.watchkitapp}"
APP_ID="${WATCH_APP_BUNDLE_ID}"
DERIVED_DATA="${ROOT_DIR}/.build/DerivedData-CompanionScheme"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug-watchos/alarm_applewatch Watch App.app"
LOG_FILE="${ROOT_DIR}/.build/watch-console-charger-transition.log"
BUILD_LOG="${ROOT_DIR}/.build/watch-charger-transition-build.log"
PRECHECK_LOG="${ROOT_DIR}/.build/watch-console-charger-precheck.log"

cd "${ROOT_DIR}"
mkdir -p .build

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  xcodebuild \
    -project alarm_applewatch.xcodeproj \
    -scheme alarm_applewatch \
    -destination "id=${IOS_DESTINATION_ID}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build >"${BUILD_LOG}"
fi

xcrun devicectl device install app \
  --device "${WATCH_DEVICE}" \
  "${APP_PATH}" \
  --timeout 120

rm -f "${PRECHECK_LOG}"
(
  xcrun devicectl device process launch \
    --device "${WATCH_DEVICE}" \
    --terminate-existing \
    --console \
    --environment-variables '{"WAKE_GUARD_CHARGER_TEST_MODE":"1"}' \
    "${APP_ID}"
) >"${PRECHECK_LOG}" 2>&1 &
precheck_pid=$!
sleep 12
kill -INT "${precheck_pid}" 2>/dev/null || true
wait "${precheck_pid}" || true

if grep -q "battery state=charging\\|battery state=full" "${PRECHECK_LOG}"; then
  tail -n 80 "${PRECHECK_LOG}"
  printf 'PRECHECK FAILED: Apple Watch is already charging. Remove it from the charger before running the transition test.\n' >&2
  exit 2
fi

if ! grep -q "battery state=unplugged" "${PRECHECK_LOG}"; then
  tail -n 80 "${PRECHECK_LOG}"
  printf 'PRECHECK FAILED: could not confirm Apple Watch is unplugged before the transition test.\n' >&2
  exit 2
fi

rm -f "${LOG_FILE}"
(
  xcrun devicectl device process launch \
    --device "${WATCH_DEVICE}" \
    --terminate-existing \
    --console \
    --environment-variables '{"WAKE_GUARD_CHARGER_TEST_MODE":"1"}' \
    "${APP_ID}"
) >"${LOG_FILE}" 2>&1 &
launcher_pid=$!

printf 'Charger-stop test launched. Log: %s\n' "${LOG_FILE}"
printf 'Keep Apple Watch off the charger until charger-diagnostic starts, then place it on the charger.\n'
printf 'Waiting 130 seconds for transition evidence...\n'

sleep 130
kill -INT "${launcher_pid}" 2>/dev/null || true
wait "${launcher_pid}" || true

tail -n 160 "${LOG_FILE}"

if grep -q "phase ended phase=charger-diagnostic .*reason=chargingDetected" "${LOG_FILE}"; then
  printf 'PASS: active phase stopped after charger detection.\n'
elif grep -q "phase skipped by charging phase=charger-diagnostic" "${LOG_FILE}"; then
  printf 'PARTIAL: Watch was already charging when the phase started, so the phase was skipped.\n'
  exit 2
else
  printf 'FAIL: no charger-stop evidence found.\n' >&2
  exit 1
fi
