# Aggressive Watch Haptic Alarm Plan

## Goal + Linked Docs

Build a personal-install Apple Watch alarm that uses an `HKWorkoutSession` as the background anchor for aggressive haptic delivery.

Done when the watch can run the fixed daily schedule, keep the haptic path alive through the workout-session anchor, fall back to local notifications when needed, bridge to Smart Alarm when active, and present only the minimal UI required for a personal install.

Linked docs:
- Product spec: none yet; approved scope is from the implementation request.
- Design doc: none yet; this plan is the active execution contract.

## Scope + Constraints

In scope:
- Fixed daily alarms at 07:40 for 5s, 07:50 for 20s, and 08:00 for 300s.
- Watch-local aggressive haptics anchored by `HKWorkoutSession` only during the morning guard window.
- Local notification fallback for alarm delivery.
- Smart Alarm bridge only when Smart Alarm is active.
- Minimal UI for setup/status only.

Out of scope:
- Stop, snooze, editable schedules, multi-user settings, cloud sync, App Store polish, analytics, and broad UI redesign.
- Any app-code work during this documentation-only planning pass.

Constraints:
- Personal-install behavior is acceptable; do not optimize for App Store review.
- Background behavior must degrade visibly through local notifications if haptic execution cannot continue.
- Routine logs for any future multi-worker/runtime path must be gated to a main process or rank.

## Slices

### Slice 1: Alarm Schedule Contract

Outcome: the app owns exactly the approved fixed daily schedule.

Acceptance criteria:
- 07:40 triggers a 5s haptic alarm.
- 07:50 triggers a 20s haptic alarm.
- 08:00 triggers a 300s haptic alarm.
- No stop, snooze, or schedule editing is exposed.

Evaluation backing:
- Primary signal: local simulator/device inspection of scheduled alarm calculation and UI surface.
- Success bar: all three fixed alarm windows are represented exactly once and no extra user controls alter them.
- If missed: correct schedule source and remove conflicting controls before continuing.

Relationships:
- Depends on: none.
- Can run in parallel with: Slice 4.
- Unblocks: Slice 2 and Slice 3.
- Complete when: schedule constants and minimal UI behavior match the approved contract.

### Slice 2: Workout-Anchored Haptic Runner

Outcome: alarm haptics run through a watch-local path kept active by `HKWorkoutSession` only during the Morning Guard window.

Acceptance criteria:
- Workout authorization/session lifecycle is handled.
- Morning Guard starts or recovers the workout anchor inside the local-time guard window and stops it outside that window.
- For the fixed morning schedule, the guard window is 07:35 through 08:06.
- Long 08:00 alarm continues attempting haptics for the full 300s window.

Evaluation backing:
- Primary signal: Apple Watch device run with console/device logs and observed haptic duration.
- Debug physical-device smoke test: app launch triggers `+10s`, `+30s`, and `+60s` diagnostic phases with 2, 5, and 10 haptic pulses at one pulse per second. This does not change the fixed daily schedule contract.
- Debug charger-stop smoke test: launch with `WAKE_GUARD_CHARGER_TEST_MODE=1` to run one `launch + 10s` phase for 90s, then place the Watch on the charger and expect `reason=chargingDetected`.
- Success bar: haptics start on time and continue for each approved duration while the workout session remains valid.
- If missed: inspect session lifecycle, authorization state, and haptic loop timing before changing product scope.

Relationships:
- Depends on: Slice 1.
- Can run in parallel with: none.
- Unblocks: Slice 3 and closure validation.
- Complete when: workout-backed haptics are demonstrably active for all three durations.

### Slice 3: Fallback + Smart Alarm Bridge

Outcome: delivery degrades through local notifications and cooperates with Smart Alarm only when it is active.

Acceptance criteria:
- Local notifications are scheduled or emitted as fallback for the fixed alarm windows.
- Notification permission state is handled.
- Smart Alarm bridge is invoked only when Smart Alarm is active.
- Smart Alarm absence or inactivity does not block watch-local alarms.

Evaluation backing:
- Primary signal: local permission-state tests plus device/manual checks for active and inactive Smart Alarm states.
- Success bar: fallback notifications fire without duplicate primary-path noise, and Smart Alarm receives bridge events only when active.
- If missed: isolate permission handling and bridge activation checks before altering alarm timing.

Relationships:
- Depends on: Slice 1 and Slice 2.
- Can run in parallel with: none.
- Unblocks: end-to-end validation.
- Complete when: fallback and bridge behavior are validated across active, inactive, and unavailable states.

### Slice 4: Minimal Personal-Install UI

Outcome: the UI shows only necessary status/setup affordances.

Acceptance criteria:
- UI exposes status needed for permissions/background readiness.
- UI does not expose stop, snooze, or schedule editing.
- Text is concise and usable on Apple Watch.

Evaluation backing:
- Primary signal: watch UI inspection on supported viewport/device.
- Success bar: user can confirm readiness without seeing unsupported controls.
- If missed: remove excess controls and tighten copy.

Relationships:
- Depends on: none.
- Can run in parallel with: Slice 1.
- Unblocks: closure validation.
- Complete when: UI matches the personal-install, no-stop/no-snooze constraint.

## Tasks

Current slice: device validation.

- [x] Confirm current app structure and permission capabilities.
- [x] Implement fixed schedule contract.
- [x] Add SwiftPM core tests for fixed schedule, pulse plans, battery stop policy, and notification descriptors.
- [x] Implement workout anchor, haptic runner, fallback notifications, Smart Alarm bridge, and minimal UI.
- [x] Run SwiftPM tests and Xcode build before closure update.
- [x] Add and run simulator diagnostic verification for phase scheduling and haptic pulse calls.
- [x] Add physical Apple Watch connection/run runbook and a non-destructive device visibility checker.
- [x] Add Debug physical-device diagnostic schedule for short haptic smoke tests without changing the 07:40 / 07:50 / 08:00 schedule contract.
- [x] Install on a physical Apple Watch and validate HealthKit authorization, background haptics after Home/Digital Crown, charger stop behavior, and fallback notification scheduling.
- [ ] Confirm from the wearer that physical diagnostic and morning-schedule haptics are felt for the expected windows.
- [ ] Decide whether Smart Alarm bridge validation remains a closure gate or is documented as best-effort residual risk.
