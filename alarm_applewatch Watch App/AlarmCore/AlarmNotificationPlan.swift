import Foundation

public struct AlarmNotificationDescriptor: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let hour: Int
    public let minute: Int

    public init(identifier: String, title: String, body: String, hour: Int, minute: Int) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.hour = hour
        self.minute = minute
    }
}

public struct AlarmNotificationPlan: Equatable, Sendable {
    public let descriptors: [AlarmNotificationDescriptor]

    public static func identifier(forPhaseID phaseID: String) -> String {
        "alarm_applewatch.daily.\(phaseID)"
    }

    public init(configuration: AlarmConfiguration) {
        descriptors = configuration.phases.map { phase in
            AlarmNotificationDescriptor(
                identifier: AlarmNotificationPlan.identifier(forPhaseID: phase.id),
                title: phase.title,
                body: "Place Apple Watch on charger to stop haptics.",
                hour: phase.hour,
                minute: phase.minute
            )
        }
    }
}
