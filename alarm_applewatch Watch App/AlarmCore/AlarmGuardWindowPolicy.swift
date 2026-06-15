import Foundation

public struct AlarmGuardWindow: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date

    public init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }

    public func contains(_ date: Date) -> Bool {
        startDate <= date && date < endDate
    }
}

public struct AlarmGuardWindowPolicy: Sendable {
    public let configuration: AlarmConfiguration
    public let prewarmSeconds: Int
    public let cooldownSeconds: Int
    public let calendar: Calendar

    public init(
        configuration: AlarmConfiguration,
        prewarmSeconds: Int = 300,
        cooldownSeconds: Int = 60,
        calendar: Calendar = .current
    ) {
        self.configuration = configuration
        self.prewarmSeconds = prewarmSeconds
        self.cooldownSeconds = cooldownSeconds
        self.calendar = calendar
    }

    public func window(onDayContaining date: Date) -> AlarmGuardWindow? {
        let calculator = AlarmScheduleCalculator(configuration: configuration, calendar: calendar)
        let scheduledPhases = calculator.scheduledPhases(onDayContaining: date)
        guard
            let firstPhase = scheduledPhases.first,
            let lastPhase = scheduledPhases.max(by: { lhs, rhs in
                lhs.startDate.addingTimeInterval(TimeInterval(lhs.phase.durationSeconds)) <
                    rhs.startDate.addingTimeInterval(TimeInterval(rhs.phase.durationSeconds))
            })
        else {
            return nil
        }

        let startDate = firstPhase.startDate.addingTimeInterval(-TimeInterval(prewarmSeconds))
        let lastPhaseEnd = lastPhase.startDate.addingTimeInterval(TimeInterval(lastPhase.phase.durationSeconds))
        let endDate = lastPhaseEnd.addingTimeInterval(TimeInterval(cooldownSeconds))

        return AlarmGuardWindow(startDate: startDate, endDate: endDate)
    }

    public func currentWindow(at date: Date) -> AlarmGuardWindow? {
        candidateWindowDates(around: date)
            .compactMap(window(onDayContaining:))
            .first { $0.contains(date) }
    }

    public func currentOrNextWindow(at date: Date) -> AlarmGuardWindow? {
        if let currentWindow = currentWindow(at: date) {
            return currentWindow
        }

        return candidateWindowDates(around: date)
            .compactMap(window(onDayContaining:))
            .filter { $0.startDate > date }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    private func candidateWindowDates(around date: Date) -> [Date] {
        [-1, 0, 1, 2].compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: date)
        }
    }
}
