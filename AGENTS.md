# Repository Guidelines

- 절대 변경 내역, AI 말투(e.g. 왜 중요한가), 메타발언, 작업 범위 설명, 방어적인 말투(e.g. 이것은 ~가 아니다) 등을 사용하지 마라.

## Project Structure & Module Organization

This repository contains a personal Apple Watch alarm app. The Xcode project lives at `alarm_applewatch.xcodeproj`. The watchOS app source is under `alarm_applewatch Watch App/`, with reusable alarm scheduling and haptic-planning logic in `alarm_applewatch Watch App/AlarmCore/`. The companion iOS app shell is in `alarm_applewatch/`. Swift package metadata in `Package.swift` exposes the `AlarmCore` library for local tests. Tests live in `Tests/AlarmCoreTests/`. Watch assets are in `alarm_applewatch Watch App/Assets.xcassets/`, operational scripts are in `scripts/`, and project documentation is in `docs/`.

Read `README.md` first for the project map, then `docs/index.md` for runbooks and active execution status.

## Build, Test, and Development Commands

- `swift test`: runs the Swift Package tests for `AlarmCore`.
- `xcodebuild -project alarm_applewatch.xcodeproj -scheme "alarm_applewatch Watch App" -destination "generic/platform=watchOS Simulator" CODE_SIGNING_ALLOWED=NO build`: builds the watch app for simulator without signing.
- `WATCH_UDID=<sim-udid> scripts/verify_watch_simulator.sh`: builds, installs, launches, and checks simulator diagnostic haptic phases.
- `scripts/check_real_watch_device.sh`: checks Xcode tools, device visibility, signing, entitlements, and generic physical-watch build readiness.
- `WATCH_DEVICE=<watch-id> IOS_DESTINATION_ID=<iphone-id> scripts/run_watch_charger_stop_test.sh`: runs the physical charger-stop validation. Use `SKIP_BUILD=1` only after a current build exists.

## Coding Style & Naming Conventions

Use Swift 6 conventions with four-space indentation. Keep type names in `UpperCamelCase` and properties, methods, enum cases, and test functions in `lowerCamelCase`. Prefer small value types and pure scheduling logic in `AlarmCore`; keep watch UI, HealthKit, notification, battery, and device integration code in the watch app target. Do not move device-specific behavior into the package target unless it can run on macOS tests.

## Testing Guidelines

Core tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`). Name tests as behavior statements, for example `scheduleCalculatorReturnsNextPhaseTodayOrTomorrow`. Add package tests for deterministic configuration, scheduling, haptic plan, notification plan, and battery policy changes. Use the simulator and real-device scripts when changing runtime behavior, haptics, charging detection, entitlements, or provisioning-sensitive code.

## Commit & Pull Request Guidelines

Use concise imperative commit subjects such as `Add charger-stop validation` and keep each commit focused. Pull requests should include a short summary, validation commands and results, linked issues or docs when relevant, and screenshots or recordings for UI changes. Note simulator/device IDs, environment overrides, and any signing or provisioning assumptions.

## Security & Configuration Tips

Do not commit provisioning profiles, certificates, derived data, personal device IDs, Team IDs, bundle IDs, or device logs. Put local script values in ignored `.env`, and local Xcode signing/bundle values in ignored `config/Local.xcconfig`.
