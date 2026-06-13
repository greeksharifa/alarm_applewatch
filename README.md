# alarm_applewatch

Personal Apple Watch alarm app focused on reliable watch-local haptic alarms, fallback notifications, and physical-device validation.

The fixed daily schedule is 07:40 for 5 seconds, 07:50 for 20 seconds, and 08:00 for 300 seconds. Debug builds also support short diagnostic schedules for simulator and physical Watch validation.

## Project Map

- `alarm_applewatch Watch App/`: watchOS app source, UI, haptics, battery monitoring, notifications, and HealthKit workout anchoring.
- `alarm_applewatch Watch App/AlarmCore/`: pure alarm configuration, scheduling, notification plan, haptic pulse plan, and battery stop policy.
- `alarm_applewatch/`: companion iOS app shell.
- `Tests/AlarmCoreTests/`: Swift Testing coverage for deterministic alarm core behavior.
- `scripts/`: simulator and physical-device verification helpers.
- `docs/`: runbooks and execution-plan documentation.

## Validation Ladder

```sh
swift test
xcodebuild -project alarm_applewatch.xcodeproj -scheme "alarm_applewatch Watch App" -destination "generic/platform=watchOS Simulator" CODE_SIGNING_ALLOWED=NO build
WATCH_UDID=<sim-udid> scripts/verify_watch_simulator.sh
bash scripts/check_real_watch_device.sh
WATCH_DEVICE=<watch-id> IOS_DESTINATION_ID=<iphone-id> scripts/run_watch_charger_stop_test.sh
```

Copy `.env.example` to `.env` for local script values. Copy `config/Local.xcconfig.example` to `config/Local.xcconfig` for local Xcode signing and bundle identifiers. Both copied files are ignored by git.

`APPLE_DEVELOPMENT_TEAM`, `IOS_APP_BUNDLE_ID`, `WATCH_APP_BUNDLE_ID`, `WATCH_UDID`, `WATCH_DEVICE`, and `IOS_DESTINATION_ID` are intentionally local values. Do not commit personal IDs, provisioning profiles, certificates, or device logs.

## Documentation

Start with [AGENTS.md](AGENTS.md) for contributor rules and [docs/index.md](docs/index.md) for the documentation map. Use [docs/real-device-watch-testing.md](docs/real-device-watch-testing.md) before relying on physical Watch behavior.
