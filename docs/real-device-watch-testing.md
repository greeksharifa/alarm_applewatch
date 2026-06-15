# Real Device Apple Watch Testing

Use this runbook when moving `alarm_applewatch Watch App` from the watchOS simulator to a physical Apple Watch.

## Preconditions

- Xcode 26.5 is installed.
- The project scheme is `alarm_applewatch Watch App`.
- The Watch target currently requires watchOS 26.5 or newer.
- The app uses HealthKit and workout background processing, so real-device validation is required for the final background haptic behavior.

## 1. Pair Apple Watch With iPhone

1. On iPhone, open the Watch app.
2. Pair the target Apple Watch with that iPhone.
3. Keep Bluetooth and Wi-Fi enabled on both devices.
4. Keep both devices unlocked and charged during the first install.

The Apple Watch is not connected directly to the Mac for normal Xcode runs. Xcode reaches the Watch through the paired iPhone.

## 2. Connect iPhone to Mac

1. Connect the iPhone to the Mac with USB.
2. Unlock the iPhone.
3. If iPhone shows `Trust This Computer?`, tap `Trust`.
4. Enter the iPhone passcode if prompted.
5. Keep the Apple Watch unlocked and near the iPhone.

## 3. Configure Signing in Xcode

1. Open `alarm_applewatch.xcodeproj`.
2. Open Xcode `Settings > Accounts` and sign in with the Apple Account used for development.
3. Select target `alarm_applewatch Watch App`.
4. Open `Signing & Capabilities`.
5. Select the intended `Team`.
6. Keep `Automatically manage signing` enabled.
7. Confirm HealthKit remains present in capabilities/entitlements.

Bundle identifiers come from local configuration:

- iOS companion: `IOS_APP_BUNDLE_ID`
- Watch app: `WATCH_APP_BUNDLE_ID`

Copy `config/Local.xcconfig.example` to ignored `config/Local.xcconfig`, then set `APPLE_DEVELOPMENT_TEAM`, `IOS_APP_BUNDLE_ID`, and `WATCH_APP_BUNDLE_ID` there. For script runs, copy `.env.example` to ignored `.env` and set the same bundle IDs plus local device identifiers. If Xcode reports that a bundle identifier is unavailable, change only the local ignored values.

## 4. Enable Developer Mode

Enable Developer Mode after Xcode has seen the devices.

On iPhone:

1. Open `Settings > Privacy & Security > Developer Mode`.
2. Turn Developer Mode on.
3. Restart if prompted.
4. After restart, confirm `Turn On`.

On Apple Watch:

1. Open `Settings > Privacy & Security > Developer Mode`.
2. Turn Developer Mode on.
3. Restart if prompted.
4. After restart, confirm `Turn On`.

If Developer Mode is not visible on Apple Watch, try one physical-device run from Xcode, then check the Watch settings again.

## 5. Verify Device Visibility

From the repository root, run:

```bash
bash scripts/check_real_watch_device.sh
```

Expected healthy result:

- `xcodebuild -list` shows scheme `alarm_applewatch Watch App`.
- `system_profiler` shows a USB-connected iPhone or iPad.
- `ioreg`, `usbmuxd`, and lockdownd can see the connected iPhone.
- `devicectl` shows the connected iPhone and paired Apple Watch.
- `xcdevice` shows a physical iPhone or Apple Watch, not only `My Mac`.
- `xctrace` shows a recording-capable physical device.
- `xcodebuild -showdestinations` shows a physical Apple Watch destination, not only placeholders or simulators.
- The signed generic watchOS build probe passes.
- The script reports the current watchOS deployment target, bundle IDs, signing team, Info.plist, and entitlement file.

If the script reports no devices or no physical Watch destination, fix physical connectivity first: unlock iPhone/Watch, reconnect USB, trust the Mac, keep Bluetooth/Wi-Fi enabled, then restart Xcode.
If the signed build probe fails, fix Xcode account login, Team, device registration, bundle IDs, and provisioning profiles before attempting the runtime validation.

## 6. Select the Physical Watch Destination

1. In Xcode, select scheme `alarm_applewatch Watch App`.
2. Open the run destination menu.
3. Select the physical Apple Watch destination, usually shown under the paired iPhone.
4. Do not select a simulator or generic `Any watchOS Device`.
5. If Xcode shows `Preparing device`, wait until it finishes.
6. If Xcode shows `Register Device`, register it.

If the Watch is listed as ineligible, confirm the Watch is running watchOS 26.5 or newer.

## 7. Run and Grant Permissions

1. Press `Cmd + R` in Xcode.
2. Wait for the app to install and launch on Apple Watch.
3. Grant HealthKit permission when prompted.
4. Grant notification permission when prompted.
5. Confirm Morning Guard is on in the Watch app UI. First launch defaults it on; explicitly turning it off persists that off state.

## Morning Guard Window

Morning Guard is not a full-night keep-alive mode. For the fixed morning schedule, the Watch app keeps the HealthKit workout anchor off outside the local-time guard window, then starts or recovers it only inside this range:

- Guard starts: `07:35`.
- Guard ends: `08:06`.
- Alarm phases inside the window: `07:40` for 5 seconds, `07:50` for 20 seconds, and `08:00` for 300 seconds.

This preserves the aggressive haptic path during the morning alarm window while avoiding a forced workout session during the rest of Sleep Focus or Do Not Disturb hours. The repeating fallback notifications are silent normal notifications because personal development teams do not support the Time Sensitive Notifications entitlement; they are a recovery layer, not the primary haptic loop.

## Debug Diagnostic Schedule

Debug builds use a short diagnostic schedule so the haptic path can be tested without waiting for the morning alarms. When the Watch app starts in Debug, the guard uses `AlarmConfiguration.deviceDiagnostic(startingAt:)` unless `WAKE_GUARD_PRODUCTION_SCHEDULE=1` is set. Simulator verification uses the same offsets and the same one-pulse-per-second cadence as the real morning alarms.

Diagnostic phases are relative to the app launch time:

- `launch + 10s`: 2 haptic pulses over 2 seconds.
- `launch + 30s`: 5 haptic pulses over 5 seconds.
- `launch + 60s`: 10 haptic pulses over 10 seconds.

This diagnostic schedule is for test runs only. The real app schedule remains the fixed local-time morning schedule:

- `07:40`: haptics for 5 seconds.
- `07:50`: haptics for 20 seconds.
- `08:00`: haptics for 300 seconds.

To test the real morning schedule from a Debug build, launch with `WAKE_GUARD_PRODUCTION_SCHEDULE=1` or use a non-Debug build.

## Simulator Wake-Window Diagnostic

Use `WAKE_GUARD_WINDOW_DIAGNOSTIC_MODE=1` when the specific behavior under test is "wake the guard shortly before a later alarm." This mode keeps the same 2/5/10 pulse pattern but moves the alarms a few minutes after launch:

- Guard prewake: `launch + 60s`.
- `launch + 120s`: 2 haptic pulses over 2 seconds.
- `launch + 150s`: 5 haptic pulses over 5 seconds.
- `launch + 180s`: 10 haptic pulses over 10 seconds.
- Guard cooldown ends at approximately `launch + 220s`.

The repeatable simulator command path is:

```sh
WATCH_UDID=<sim-udid> bash scripts/verify_watch_simulator_wake_window.sh
```

Expected log evidence includes `guard armed window_start=...` before the first phase, the three diagnostic phase start/end records, the tenth pulse in `diagnostic-3`, and `workout anchor stop requested` plus `workout session state=3` after the guard window completes. This validates the app's scheduled prewake loop and confirms the workout anchor is released after the diagnostic window. It does not prove that watchOS will relaunch a terminated app; that still requires physical Watch validation with Smart Alarm/fallback behavior.

If the simulator shows a Health Access prompt, approve it before the guard prewake time. Otherwise the workout anchor authorization request can block the phase loop before haptics begin. This is expected on a fresh simulator that has not previously granted HealthKit access.

## Manual Haptic Test Button

The Watch app UI has a `Test Haptics` button for immediate wearer validation. It runs the same one-pulse-per-second cadence as the diagnostic haptic test without waiting for launch offsets:

- `Manual Test 1`: 2 haptic pulses over 2 seconds.
- `Manual Test 2`: 5 haptic pulses over 5 seconds.
- `Manual Test 3`: 10 haptic pulses over 10 seconds.

This button is only a manual haptic smoke test. It does not change the fixed morning schedule and it is not a stop, snooze, or cancel control. If the Watch is charging before or during the manual test, the same charging stop policy skips or stops the current manual phase.

## Charger Stop Diagnostic

Debug builds also include a charger-stop diagnostic mode that does not change the default Debug diagnostic schedule. Launch the Watch app with `WAKE_GUARD_CHARGER_TEST_MODE=1` to schedule one phase at `launch + 10s` that runs for 90 seconds.

Use this mode only for physical Watch testing:

- Launch with `WAKE_GUARD_CHARGER_TEST_MODE=1`.
- Wait for `charger-diagnostic` to start.
- Place Apple Watch on the charger during the active phase.
- Expected console result: `battery state=charging` or `battery state=full`, followed by `phase ended phase=charger-diagnostic ... reason=chargingDetected`.

The repeatable command path is:

```sh
WATCH_DEVICE=<watch-id> IOS_DESTINATION_ID=<iphone-id> WATCH_APP_BUNDLE_ID=<watch-bundle-id> scripts/run_watch_charger_stop_test.sh
```

Find identifiers with `xcrun devicectl list devices` and `xcodebuild -project alarm_applewatch.xcodeproj -scheme alarm_applewatch -showdestinations`. Run it with the Watch off the charger. The script builds, installs, performs a short precheck that must record `battery state=unplugged`, launches with `WAKE_GUARD_CHARGER_TEST_MODE=1`, captures the device console, waits 130 seconds, and exits successfully only when the active phase ends with `reason=chargingDetected`. Use `SKIP_BUILD=1` only when the current `.build/DerivedData-CompanionScheme` output already exists. If the Watch is already charging before the test begins, it exits early with partial status.

## 8. Validate Real-Device Behavior

Physical Watch validation must cover these cases:

- In Debug diagnostic mode, app launch triggers the `+10s`, `+30s`, and `+60s` phases with 2, 5, and 10 haptic pulses at one pulse per second.
- 07:40 alarm runs haptics for 5 seconds.
- 07:50 alarm runs haptics for 20 seconds.
- 08:00 alarm keeps attempting haptics for 300 seconds.
- Outside `07:35` through `08:06`, the workout anchor returns to off/idle instead of staying active through Sleep Focus hours.
- Pressing Home/Digital Crown during an active phase does not immediately stop the phase while the workout anchor remains valid.
- Placing the Watch on a charger stops the active phase within the battery polling window.
- Local fallback notifications remain scheduled after app relaunch or Watch restart.
- Smart Alarm bridge behavior does not block watch-local alarms when Smart Alarm is inactive or unavailable.

Record the observed behavior in `docs/exec-plans/active/aggressive-watch-haptic-alarm/CLOSURE.md` before closing the active plan.

## Troubleshooting

- Watch not visible in Xcode: reconnect USB, unlock iPhone and Watch, trust the Mac, keep Bluetooth/Wi-Fi enabled, restart Xcode.
- If `ioreg`, `usbmuxd`, or lockdownd can see the iPhone but `devicectl`, `xcdevice list`, and `xcodebuild -showdestinations` still cannot, fully quit Xcode and reopen it. If CoreDevice/CoreSimulator connection errors continue, reboot the Mac before retrying.
- Developer Mode not visible: attempt one Xcode run to the physical Watch, then recheck settings.
- Signing fails: confirm Team, automatic signing, unique bundle IDs, and HealthKit capability.
- Destination is ineligible: update Apple Watch to watchOS 26.5 or lower the deployment target only after confirming the app still supports the older runtime.
- HealthKit authorization fails: verify entitlements, signing profile, and Watch privacy prompts.

## Official References

- [Apple Developer: Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Apple Developer: Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Apple Support: Set up and pair your Apple Watch with iPhone](https://support.apple.com/guide/watch/set-up-and-pair-your-apple-watch-with-iphone-apdde4d6f98e/watchos)
- [Apple Developer: Supported capabilities for watchOS](https://developer.apple.com/help/account/reference/supported-capabilities-watchos/)
