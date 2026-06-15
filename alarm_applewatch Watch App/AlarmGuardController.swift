import Foundation
import Combine
import OSLog
import SwiftUI
import WatchKit

@MainActor
final class AlarmGuardController: ObservableObject {
    static let shared = AlarmGuardController()

    @Published private(set) var isAggressiveModeEnabled: Bool
    @Published private(set) var scheduleText: String
    @Published private(set) var nextPhaseText = "Next: Not scheduled"
    @Published private(set) var currentPhaseText = "Idle"
    @Published private(set) var lastEventText: String
    @Published private(set) var isManualHapticTestRunning = false

    let batteryMonitor = BatteryStopMonitor()
    let workoutAnchor = WorkoutBackgroundAnchor()

    private let configuration: AlarmConfiguration
    private let hapticRunner = HapticPhaseRunner()
    private let notificationScheduler = LongTermNotificationScheduler()
    private lazy var smartAlarmBridge = SmartAlarmBridge { [weak self] event in
        self?.lastEventText = event
    }
    private var guardTask: Task<Void, Never>?
    private var manualHapticTestTask: Task<Void, Never>?
    private var guardGeneration = 0
    private var calendar = Calendar.current

    private let enabledKey = "AggressiveModeEnabled"
    private let guardWindowPrewarmSeconds: Int
    private let guardWindowCooldownSeconds: Int

    private init() {
        let environment = ProcessInfo.processInfo.environment
        let chargerTestMode = AlarmGuardController.shouldRunChargerTestMode(environment: environment)
        let wakeWindowDiagnosticMode = AlarmGuardController.shouldRunWakeWindowDiagnosticMode(environment: environment)
        let diagnosticMode = AlarmGuardController.shouldRunDiagnosticMode(environment: environment)
        let forceEnabled = chargerTestMode || wakeWindowDiagnosticMode || diagnosticMode
        let storedAggressiveModePreference = UserDefaults.standard.object(forKey: enabledKey) as? Bool
        if chargerTestMode {
            configuration = AlarmConfiguration.chargerDiagnostic(startingAt: Date())
            guardWindowPrewarmSeconds = 300
            guardWindowCooldownSeconds = 60
        } else if wakeWindowDiagnosticMode {
            configuration = AlarmConfiguration.simulatorWakeWindowDiagnostic(startingAt: Date())
            guardWindowPrewarmSeconds = 60
            guardWindowCooldownSeconds = 30
        } else if diagnosticMode {
            configuration = AlarmConfiguration.deviceDiagnostic(startingAt: Date())
            guardWindowPrewarmSeconds = 300
            guardWindowCooldownSeconds = 60
        } else {
            configuration = .fixedDaily
            guardWindowPrewarmSeconds = 300
            guardWindowCooldownSeconds = 60
        }
        scheduleText = AlarmGuardController.scheduleSummary(for: configuration)
        let resolvedAggressiveModeEnabled = AggressiveModePreference.resolve(
            storedValue: storedAggressiveModePreference,
            forceEnabled: forceEnabled
        )
        isAggressiveModeEnabled = resolvedAggressiveModeEnabled
        if storedAggressiveModePreference == nil && !forceEnabled {
            UserDefaults.standard.set(resolvedAggressiveModeEnabled, forKey: enabledKey)
        }
        if chargerTestMode {
            lastEventText = "Charger test ready"
        } else if wakeWindowDiagnosticMode {
            lastEventText = "Wake window diagnostic ready"
        } else if diagnosticMode {
            lastEventText = "Diagnostic mode ready"
        } else {
            lastEventText = "Ready"
        }
    }

    func bootstrap() {
        Task {
            AlarmLog.runtime.info("bootstrap enabled=\(self.isAggressiveModeEnabled) schedule=\(self.scheduleText, privacy: .public)")
            AlarmDebugConsole.write("bootstrap enabled=\(self.isAggressiveModeEnabled) schedule=\(self.scheduleText)")

            if isAggressiveModeEnabled {
                startGuardLoop()
            }

            await notificationScheduler.requestAuthorizationAndSchedule(configuration: .fixedDaily)
        }
    }

    func setAggressiveModeEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        isAggressiveModeEnabled = enabled

        if enabled {
            AlarmLog.runtime.info("morning guard enabled")
            startGuardLoop()
        } else {
            AlarmLog.runtime.info("morning guard disabled")
            guardGeneration += 1
            guardTask?.cancel()
            guardTask = nil
            workoutAnchor.stop()
            currentPhaseText = "Idle"
            lastEventText = "Morning Guard off"
        }
    }

    var canRunManualHapticTest: Bool {
        !isManualHapticTestRunning && !currentPhaseText.hasPrefix("Running")
    }

    func runManualHapticTest() {
        guard canRunManualHapticTest else {
            lastEventText = "Manual haptic test already running"
            return
        }

        manualHapticTestTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.runManualHapticTestSequence()
            self.manualHapticTestTask = nil
        }
    }

    func handleExtendedRuntimeSession(_ session: WKExtendedRuntimeSession) {
        lastEventText = "Smart Alarm bridge woke app"
        if isAggressiveModeEnabled {
            startGuardLoop()
        }
    }

    private func startGuardLoop() {
        guard guardTask == nil else {
            AlarmLog.runtime.info("guard loop already running")
            return
        }

        guardGeneration += 1
        let generation = guardGeneration
        guardTask = Task { [weak self] in
            guard let self else { return }
            await self.runGuardLoop()

            if self.guardGeneration == generation {
                self.guardTask = nil
            }
        }
    }

    private func runGuardLoop() async {
        AlarmLog.runtime.info("guard loop starting")
        AlarmDebugConsole.write("guard loop starting")
        let calculator = AlarmScheduleCalculator(configuration: configuration, calendar: calendar)
        let windowPolicy = AlarmGuardWindowPolicy(
            configuration: configuration,
            prewarmSeconds: guardWindowPrewarmSeconds,
            cooldownSeconds: guardWindowCooldownSeconds,
            calendar: calendar
        )

        while !Task.isCancelled && isAggressiveModeEnabled {
            batteryMonitor.refresh()

            let now = Date()
            guard let guardWindow = windowPolicy.currentOrNextWindow(at: now) else {
                workoutAnchor.stop()
                nextPhaseText = "Next: unavailable"
                currentPhaseText = "Guard window unavailable"
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                continue
            }

            if now < guardWindow.startDate {
                workoutAnchor.stop()
                nextPhaseText = "Next guard: \(formatted(guardWindow.startDate))"
                currentPhaseText = "Armed, anchor off"
                lastEventText = "Guard window starts \(formatted(guardWindow.startDate))"
                AlarmLog.runtime.info("guard armed window_start=\(self.formatted(guardWindow.startDate), privacy: .public) window_end=\(self.formatted(guardWindow.endDate), privacy: .public)")
                AlarmDebugConsole.write("guard armed window_start=\(formatted(guardWindow.startDate)) window_end=\(formatted(guardWindow.endDate))")
                smartAlarmBridge.scheduleIfActive(at: guardWindow.startDate)
                await sleepUntil(guardWindow.startDate)
                continue
            }

            await workoutAnchor.startOrRecover()

            guard let scheduled = calculator.currentOrNextPhase(at: now) else {
                nextPhaseText = "Next: unavailable"
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                continue
            }

            if scheduled.startDate >= guardWindow.endDate {
                workoutAnchor.stop()
                currentPhaseText = "Morning guard complete"
                nextPhaseText = "Next guard: \(formatted(windowPolicy.currentOrNextWindow(at: guardWindow.endDate)?.startDate ?? guardWindow.endDate))"
                lastEventText = "Anchor off outside alarm window"
                AlarmLog.runtime.info("guard window complete window_end=\(self.formatted(guardWindow.endDate), privacy: .public)")
                AlarmDebugConsole.write("guard window complete window_end=\(formatted(guardWindow.endDate))")
                await sleepUntil(guardWindow.endDate)
                continue
            }

            let phaseLabel = scheduled.startDate <= now ? "Current" : "Next"
            nextPhaseText = "\(phaseLabel): \(formatted(scheduled.startDate)) \(scheduled.phase.title)"
            currentPhaseText = "Waiting"
            AlarmLog.runtime.info("guard scheduled \(scheduled.phase.id, privacy: .public) at \(self.formatted(scheduled.startDate), privacy: .public) duration=\(scheduled.phase.durationSeconds)")
            AlarmDebugConsole.write("guard scheduled phase=\(scheduled.phase.id) at=\(formatted(scheduled.startDate)) run=\(phaseRunMetric(scheduled.phase))")
            smartAlarmBridge.scheduleIfActive(at: scheduled.startDate)

            await sleepUntil(scheduled.startDate)

            guard !Task.isCancelled, isAggressiveModeEnabled else {
                break
            }

            batteryMonitor.refresh()
            let phaseEndDate = scheduled.startDate.addingTimeInterval(TimeInterval(scheduled.phase.durationSeconds))
            if batteryMonitor.shouldStopCurrentPhase {
                currentPhaseText = "\(scheduled.phase.title) skipped: charging"
                lastEventText = "Charging detected at phase start"
                AlarmLog.runtime.info("phase skipped by charging \(scheduled.phase.id, privacy: .public)")
                AlarmDebugConsole.write("phase skipped by charging phase=\(scheduled.phase.id)")
                await sleepUntil(phaseEndDate)
                continue
            }

            await workoutAnchor.startOrRecover()
            currentPhaseText = "Running \(scheduled.phase.title) for \(phaseRunMetric(scheduled.phase))"
            lastEventText = "Haptics started \(formatted(Date()))"
            AlarmLog.runtime.info("phase started \(scheduled.phase.id, privacy: .public) duration=\(scheduled.phase.durationSeconds)")
            AlarmDebugConsole.write("phase started phase=\(scheduled.phase.id) run=\(phaseRunMetric(scheduled.phase))")
            let result = await hapticRunner.run(phase: scheduled.phase) { [weak self] in
                self?.batteryMonitor.refresh()
                return self?.batteryMonitor.shouldStopCurrentPhase ?? true
            }
            currentPhaseText = phaseResultText(result)
            lastEventText = "Haptics ended \(formatted(Date()))"
            AlarmLog.runtime.info("phase ended \(result.phase.id, privacy: .public) pulses=\(result.deliveredPulses) reason=\(String(describing: result.endReason), privacy: .public)")
            AlarmDebugConsole.write("phase ended phase=\(result.phase.id) pulses=\(result.deliveredPulses) reason=\(result.endReason)")

            if result.endReason == .chargingDetected {
                await sleepUntil(phaseEndDate)
            }
        }

        workoutAnchor.stop()
        AlarmLog.runtime.info("guard loop stopped")
        AlarmDebugConsole.write("guard loop stopped")
    }

    private func runManualHapticTestSequence() async {
        isManualHapticTestRunning = true
        defer {
            isManualHapticTestRunning = false
        }

        batteryMonitor.refresh()
        guard !batteryMonitor.shouldStopCurrentPhase else {
            currentPhaseText = "Manual test skipped: charging"
            lastEventText = "Charging detected before manual test"
            AlarmLog.runtime.info("manual haptic test skipped by charging")
            AlarmDebugConsole.write("manual haptic test skipped by charging")
            return
        }

        lastEventText = "Manual haptic test started \(formatted(Date()))"
        AlarmLog.runtime.info("manual haptic test started")
        AlarmDebugConsole.write("manual haptic test started")

        for phase in AlarmConfiguration.manualHapticTestPhases {
            guard !Task.isCancelled else {
                currentPhaseText = "Manual test cancelled"
                lastEventText = "Manual haptic test cancelled"
                AlarmLog.runtime.info("manual haptic test cancelled")
                AlarmDebugConsole.write("manual haptic test cancelled")
                return
            }

            batteryMonitor.refresh()
            if batteryMonitor.shouldStopCurrentPhase {
                currentPhaseText = "\(phase.title) skipped: charging"
                lastEventText = "Charging detected during manual test"
                AlarmLog.runtime.info("manual haptic test stopped before \(phase.id, privacy: .public) by charging")
                AlarmDebugConsole.write("manual haptic test stopped before phase=\(phase.id) by charging")
                return
            }

            currentPhaseText = "Running \(phase.title) for \(phaseRunMetric(phase))"
            AlarmLog.runtime.info("manual phase started \(phase.id, privacy: .public)")
            AlarmDebugConsole.write("manual phase started phase=\(phase.id) run=\(phaseRunMetric(phase))")

            let result = await hapticRunner.run(phase: phase) { [weak self] in
                self?.batteryMonitor.refresh()
                return self?.batteryMonitor.shouldStopCurrentPhase ?? true
            }

            currentPhaseText = phaseResultText(result)
            AlarmLog.runtime.info("manual phase ended \(result.phase.id, privacy: .public) pulses=\(result.deliveredPulses) reason=\(String(describing: result.endReason), privacy: .public)")
            AlarmDebugConsole.write("manual phase ended phase=\(result.phase.id) pulses=\(result.deliveredPulses) reason=\(result.endReason)")

            guard result.endReason == .completed else {
                lastEventText = "Manual haptic test ended \(formatted(Date()))"
                return
            }

            if phase.id != AlarmConfiguration.manualHapticTestPhases.last?.id {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        currentPhaseText = "Manual test complete"
        lastEventText = "Manual haptic test ended \(formatted(Date()))"
        AlarmLog.runtime.info("manual haptic test completed")
        AlarmDebugConsole.write("manual haptic test completed")
    }

    private func sleepUntil(_ date: Date) async {
        let seconds = max(0, date.timeIntervalSince(Date()))
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func phaseResultText(_ result: HapticPhaseResult) -> String {
        switch result.endReason {
        case .completed:
            return "\(result.phase.title) complete (\(result.deliveredPulses) pulses)"
        case .chargingDetected:
            return "\(result.phase.title) stopped by charger"
        case .cancelled:
            return "\(result.phase.title) cancelled"
        }
    }

    private func phaseRunMetric(_ phase: AlarmPhase) -> String {
        return "\(phase.durationSeconds)s"
    }

    private static func scheduleSummary(for configuration: AlarmConfiguration) -> String {
        configuration.phases
            .map { phase in
                let metric = "\(phase.durationSeconds)s"
                return String(format: "%02d:%02d:%02d %@", phase.hour, phase.minute, phase.second, metric)
            }
            .joined(separator: " | ")
    }

    private static func shouldRunDiagnosticMode(environment: [String: String]) -> Bool {
        if environment["WAKE_GUARD_DIAGNOSTIC_MODE"] == "1" {
            return true
        }

        #if DEBUG
        return environment["WAKE_GUARD_PRODUCTION_SCHEDULE"] != "1"
        #else
        return false
        #endif
    }

    private static func shouldRunWakeWindowDiagnosticMode(environment: [String: String]) -> Bool {
        environment["WAKE_GUARD_WINDOW_DIAGNOSTIC_MODE"] == "1"
    }

    private static func shouldRunChargerTestMode(environment: [String: String]) -> Bool {
        environment["WAKE_GUARD_CHARGER_TEST_MODE"] == "1"
    }
}
