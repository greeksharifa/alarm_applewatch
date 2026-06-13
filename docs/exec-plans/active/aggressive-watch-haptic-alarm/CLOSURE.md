# Aggressive Watch Haptic Alarm Closure

## Closure Decision

continue

The implementation is in place and validated through physical Apple Watch console evidence. Closure still requires wearer confirmation that the haptics were felt on the wrist, because console evidence proves `WKInterfaceDevice.play(_:)` calls but cannot directly prove tactile perception.

## Evidence

Current evidence:
- Fixed schedule implemented: 07:40 for 5s, 07:50 for 20s, 08:00 for 300s.
- `AlarmGuardController` starts or recovers a long-lived `HKWorkoutSession` while Aggressive Mode is enabled.
- `HapticPhaseRunner` drives repeated `WKInterfaceDevice.play(.notification)` calls for each phase.
- `BatteryStopMonitor` cancels the current phase when Watch reports `.charging` or `.full`.
- `LongTermNotificationScheduler` registers three repeating daily fallback notifications.
- `SmartAlarmBridge` schedules best-effort extended runtime sessions only while the app is active and the start date is within 36 hours.
- Minimal Watch UI exposes Aggressive Mode and status only; it does not expose stop, snooze, cancel, or schedule editing.
- `WatchAppInfo.plist` includes HealthKit usage descriptions and `WKBackgroundModes = [workout-processing, alarm]`.
- `plutil -lint WatchAppInfo.plist` passed.
- `SWIFTPM_CACHE_PATH=.build/swiftpm-cache CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --disable-sandbox --scratch-path .build` passed 12 tests.
- `xcodebuild -quiet -project alarm_applewatch.xcodeproj -scheme 'alarm_applewatch Watch App' -destination 'generic/platform=watchOS' -derivedDataPath .build/DerivedData-FinalDevice CODE_SIGNING_ALLOWED=NO build` passed.
- `xcodebuild -quiet -project alarm_applewatch.xcodeproj -scheme 'alarm_applewatch Watch App' -destination 'generic/platform=watchOS Simulator' -derivedDataPath .build/DerivedData-FinalSim CODE_SIGNING_ALLOWED=NO build` passed.
- Built app Info.plist inspection confirmed `WKBackgroundModes` contains `workout-processing` and `alarm` for the physical watchOS product.
- Simulator diagnostic launch on Apple Watch SE 3 (44mm) watchOS 26.5 ran diagnostic phases once each with matching haptic pulse logs.
- `scripts/verify_watch_simulator.sh` passed and now reproduces the simulator diagnostic install/launch/log verification flow.
- Simulator testing found and fixed two runtime bugs: fallback notification authorization was blocking guard startup, and the haptic runner returned before the requested duration elapsed.
- Simulator testing also found that watchOS simulator does not support `simctl status_bar` battery overrides, so charger-stop behavior cannot be proven there.
- Simulator testing confirmed watchOS simulator normal builds degrade the workout anchor with `Missing com.apple.developer.healthkit entitlement`; forcing that entitlement into the simulator signature makes launch fail. Workout-backed background execution still requires physical Watch validation.
- `bash scripts/check_real_watch_device.sh` now confirms the signed generic watchOS build probe passes.
- `codesign -d --entitlements :- '.build/DerivedData-RealDeviceCheck/Build/Products/Debug-watchos/alarm_applewatch Watch App.app'` confirmed the signed Watch app includes `com.apple.developer.healthkit`.
- `docs/real-device-watch-testing.md` now documents the physical iPhone/Apple Watch pairing, Xcode signing, Developer Mode, run destination, permission, and validation checklist.
- `scripts/check_real_watch_device.sh` now performs a non-destructive local readiness check for Xcode, scheme visibility, target settings, entitlements, USB-connected iPhone visibility through `system_profiler`, `ioreg`, `usbmuxd`, and lockdownd, CoreDevice-discovered devices, `xcdevice`, `xctrace`, physical Watch destinations, and signed generic watchOS build readiness.
- `bash -n scripts/check_real_watch_device.sh` passed.
- Physical Watch CoreDevice access recovered after the Watch joined the same Wi-Fi as the Mac/iPhone: `devicectl device info details` reported `tunnelState: connected`, `ddiServicesAvailable: true`, and install/launch capabilities.
- Direct physical Watch install succeeded for the locally configured `WATCH_APP_BUNDLE_ID`.
- Direct physical Watch launch succeeded, and `devicectl device info processes` still showed the app process alive 75 seconds after launch.
- Debug physical-device diagnostic schedule is documented and implemented as app launch `+10s`, `+30s`, and `+60s` phases with 2, 5, and 10 haptic pulses at one pulse per second. The fixed daily schedule remains 07:40 for 5s, 07:50 for 20s, and 08:00 for 300s.
- Direct physical Watch console capture on 2026-06-14 launched the app at 19:32:26 KST and recorded `diagnostic-1` at 19:32:36 for 2 pulses, `diagnostic-2` at 19:32:56 for 5 pulses, and `diagnostic-3` at 19:33:26 for 10 pulses. All three ended with `reason=completed`.
- Direct physical Watch console capture after switching diagnostic mode to the short diagnostic sequence recorded `diagnostic-1` with 2 pulses, `diagnostic-2` with 5 pulses, and `diagnostic-3` with 10 pulses. All three ended with `reason=completed`; a fresh physical re-test is still needed after the 1Hz cadence change.
- Direct physical Watch foreground-loss test launched Settings while the alarm app was no longer frontmost; after that, `diagnostic-3` still started and completed 10 pulses with `reason=completed`.
- Debug charger-stop diagnostic mode is implemented behind `WAKE_GUARD_CHARGER_TEST_MODE=1` as a `launch + 10s` phase that runs for 90s so a physical charger-stop action can be tested without waiting for the 08:00 alarm.
- Direct physical Watch console capture while the Watch was already on the charger recorded `battery state=charging` at app launch and `phase skipped by charging phase=charger-diagnostic` at the scheduled phase start.
- Direct physical Watch console capture after installing the 90s charger diagnostic build again recorded `battery state=charging`, `schedule=... 90s`, and `phase skipped by charging phase=charger-diagnostic`.
- Direct physical Watch charger-transition test passed with `scripts/run_watch_charger_stop_test.sh`: the test started with `battery state=unplugged`, ran `charger-diagnostic`, delivered 12 haptic pulses, then recorded `battery state=charging` and `phase ended phase=charger-diagnostic pulses=12 reason=chargingDetected`.
- Direct physical Watch production-schedule launch with `WAKE_GUARD_PRODUCTION_SCHEDULE=1` recorded fallback notification authorization `true` and scheduled `alarm_applewatch.daily.first` at 07:40, `alarm_applewatch.daily.second` at 07:50, and `alarm_applewatch.daily.third` at 08:00.
- Fallback notification scheduling was fixed so Debug diagnostic and charger-test launches still schedule only the real 07:40 / 07:50 / 08:00 notifications. The scheduler now removes obsolete diagnostic notification identifiers before scheduling the fixed daily fallback set.
- Direct physical Watch validation after that fix recorded `fallback notification removed obsolete diagnostic ids=4`, then scheduled `alarm_applewatch.daily.first` at 07:40, `alarm_applewatch.daily.second` at 07:50, and `alarm_applewatch.daily.third` at 08:00 during a Debug diagnostic launch.
- Smart Alarm bridge Info.plist mode was corrected from the invalid `smart-alarm` string to Apple's `alarm` `WKBackgroundModes` value. In the devicectl-launched validation context, `WKExtendedRuntimeSession` still invalidated because scheduling must happen while the app is active and before `applicationWillResignActive`; the workout anchor remains the primary background execution path and local notifications remain the validated fallback.
- The Watch UI now includes a `Test Haptics` button that immediately runs the same 2/5/10-pulse, one-pulse-per-second sequence used by diagnostic testing, with no stop/snooze/cancel control added.

Pending evidence before close:
- Tactile confirmation from the wearer that the diagnostic and morning-schedule haptics are felt for the expected windows.
- Smart Alarm bridge validation from a user-driven foreground interaction, if this optional fallback is kept as a closure requirement instead of documented as best-effort residual risk.

## What Remains

- Grant HealthKit and notification permissions, enable Aggressive Mode if needed, and observe the next alarm windows.
- Use the Debug physical-device diagnostic schedule for quick haptic smoke tests before waiting for the morning schedule.
- Confirm whether the wearer felt the physical haptic pulses during diagnostic runs.
- Decide whether Smart Alarm bridge should remain best-effort or be promoted into a required closure gate.
- Decide whether to create permanent product/design docs if this personal-install behavior becomes durable project direction.
