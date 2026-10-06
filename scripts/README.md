# Script Guide

Run scripts from the repository root unless noted otherwise.

For local values, copy `.env.example` to `.env` and fill in only your machine-specific identifiers. `.env` is ignored by git.

## `verify_watch_simulator.sh`

Builds the watch app for the watchOS simulator, installs it, launches diagnostic mode, and checks expected phase/pulse log evidence.

```sh
WATCH_UDID=<sim-udid> scripts/verify_watch_simulator.sh
```

Find simulator IDs with:

```sh
xcrun simctl list devices
```

## `verify_watch_simulator_wake_window.sh`

Builds and launches the simulator wake-window diagnostic, then checks guard scheduling, all three diagnostic phase starts and completions, and the tenth pulse of the final phase.

```sh
WATCH_UDID=<sim-udid> bash scripts/verify_watch_simulator_wake_window.sh
```

The diagnostic schedules guard prewake at launch + 60s and phases at launch + 120s, +150s, and +180s. The script waits 245 seconds by default; override `WAIT_SECONDS` when needed. Simulator evidence does not replace physical Watch validation of background execution or felt haptics.

## `check_real_watch_device.sh`

Checks Xcode tools, signing settings, entitlements, USB/CoreDevice visibility, destinations, and generic physical-watch build readiness.

```sh
bash scripts/check_real_watch_device.sh
```

## `run_watch_charger_stop_test.sh`

Builds through the paired iPhone destination, installs on the physical Watch, launches charger diagnostic mode, and verifies that charging stops the active haptic phase.

```sh
WATCH_DEVICE=<watch-id> IOS_DESTINATION_ID=<iphone-id> scripts/run_watch_charger_stop_test.sh
```

Find device identifiers with:

```sh
xcrun devicectl list devices
xcodebuild -project alarm_applewatch.xcodeproj -scheme alarm_applewatch -showdestinations
```

Use `SKIP_BUILD=1` only after confirming the current build output exists in `.build/DerivedData-CompanionScheme`.
