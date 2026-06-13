import Foundation

public struct AlarmPhase: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let hour: Int
    public let minute: Int
    public let second: Int
    public let durationSeconds: Int

    public init(
        id: String,
        title: String,
        hour: Int,
        minute: Int,
        second: Int = 0,
        durationSeconds: Int
    ) {
        self.id = id
        self.title = title
        self.hour = hour
        self.minute = minute
        self.second = second
        self.durationSeconds = durationSeconds
    }

    public func withDurationSeconds(_ durationSeconds: Int) -> AlarmPhase {
        AlarmPhase(
            id: id,
            title: title,
            hour: hour,
            minute: minute,
            second: second,
            durationSeconds: durationSeconds
        )
    }
}

public struct AlarmConfiguration: Equatable, Sendable {
    private static let shortDiagnosticOffsetsAndDurations = [(10, 2), (30, 5), (60, 10)]

    public let phases: [AlarmPhase]

    public init(phases: [AlarmPhase]) {
        self.phases = phases
    }

    public static let fixedDaily = AlarmConfiguration(phases: [
        AlarmPhase(id: "first", title: "Wake 1", hour: 7, minute: 40, durationSeconds: 5),
        AlarmPhase(id: "second", title: "Wake 2", hour: 7, minute: 50, durationSeconds: 20),
        AlarmPhase(id: "third", title: "Wake 3", hour: 8, minute: 0, durationSeconds: 300)
    ])

    public static let manualHapticTestPhases = [
        AlarmPhase(id: "manual-test-1", title: "Manual Test 1", hour: 0, minute: 0, durationSeconds: 2),
        AlarmPhase(id: "manual-test-2", title: "Manual Test 2", hour: 0, minute: 0, durationSeconds: 5),
        AlarmPhase(id: "manual-test-3", title: "Manual Test 3", hour: 0, minute: 0, durationSeconds: 10)
    ]

    public static func simulatorDiagnostic(startingAt date: Date, calendar: Calendar = .current) -> AlarmConfiguration {
        diagnostic(startingAt: date, offsetsAndDurations: shortDiagnosticOffsetsAndDurations, calendar: calendar)
    }

    public static func deviceDiagnostic(startingAt date: Date, calendar: Calendar = .current) -> AlarmConfiguration {
        diagnostic(startingAt: date, offsetsAndDurations: shortDiagnosticOffsetsAndDurations, calendar: calendar)
    }

    public static func chargerDiagnostic(startingAt date: Date, calendar: Calendar = .current) -> AlarmConfiguration {
        guard let phaseDate = calendar.date(byAdding: .second, value: 10, to: date) else {
            return AlarmConfiguration(phases: [])
        }

        let components = calendar.dateComponents([.hour, .minute, .second], from: phaseDate)
        guard let hour = components.hour, let minute = components.minute, let second = components.second else {
            return AlarmConfiguration(phases: [])
        }

        return AlarmConfiguration(phases: [
            AlarmPhase(
                id: "charger-diagnostic",
                title: "Charger Test",
                hour: hour,
                minute: minute,
                second: second,
                durationSeconds: 90
            )
        ])
    }

    private static func diagnostic(
        startingAt date: Date,
        offsetsAndDurations: [(Int, Int)],
        calendar: Calendar
    ) -> AlarmConfiguration {
        let phases = offsetsAndDurations.enumerated().compactMap { index, item -> AlarmPhase? in
            let (offsetSeconds, durationSeconds) = item
            guard let phaseDate = calendar.date(byAdding: .second, value: offsetSeconds, to: date) else {
                return nil
            }

            let components = calendar.dateComponents([.hour, .minute, .second], from: phaseDate)
            guard let hour = components.hour, let minute = components.minute, let second = components.second else {
                return nil
            }

            return AlarmPhase(
                id: "diagnostic-\(index + 1)",
                title: "Diagnostic \(index + 1)",
                hour: hour,
                minute: minute,
                second: second,
                durationSeconds: durationSeconds
            )
        }

        return AlarmConfiguration(phases: phases)
    }
}

public struct ScheduledAlarmPhase: Equatable, Sendable {
    public let phase: AlarmPhase
    public let startDate: Date
}

public struct AlarmScheduleCalculator: Sendable {
    public let configuration: AlarmConfiguration
    public let calendar: Calendar

    public init(configuration: AlarmConfiguration, calendar: Calendar = .current) {
        self.configuration = configuration
        self.calendar = calendar
    }

    public func nextPhase(after date: Date) -> ScheduledAlarmPhase? {
        let candidates = scheduledPhases(onDayContaining: date) + scheduledPhases(onDayContaining: calendar.date(byAdding: .day, value: 1, to: date) ?? date)
        return candidates
            .filter { $0.startDate > date }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    public func currentOrNextPhase(at date: Date) -> ScheduledAlarmPhase? {
        if let activePhase = activePhase(at: date) {
            return activePhase
        }

        return nextPhase(after: date)
    }

    public func scheduledPhases(onDayContaining date: Date) -> [ScheduledAlarmPhase] {
        configuration.phases.compactMap { phase in
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = phase.hour
            components.minute = phase.minute
            components.second = phase.second

            guard let startDate = calendar.date(from: components) else {
                return nil
            }

            return ScheduledAlarmPhase(phase: phase, startDate: startDate)
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func activePhase(at date: Date) -> ScheduledAlarmPhase? {
        scheduledPhases(onDayContaining: date).first { scheduledPhase in
            let endDate = scheduledPhase.startDate.addingTimeInterval(TimeInterval(scheduledPhase.phase.durationSeconds))
            return scheduledPhase.startDate <= date && date < endDate
        }
        .map { scheduledPhase in
            let elapsedSeconds = max(0, Int(date.timeIntervalSince(scheduledPhase.startDate).rounded(.down)))
            let remainingSeconds = max(1, scheduledPhase.phase.durationSeconds - elapsedSeconds)
            return ScheduledAlarmPhase(
                phase: scheduledPhase.phase.withDurationSeconds(remainingSeconds),
                startDate: date
            )
        }
    }
}
