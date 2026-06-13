import Foundation
import OSLog
import UserNotifications

final class LongTermNotificationScheduler {
    private let obsoleteDiagnosticPhaseIDs = [
        "diagnostic-1",
        "diagnostic-2",
        "diagnostic-3",
        "charger-diagnostic"
    ]

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationAndSchedule(configuration: AlarmConfiguration) async {
        do {
            AlarmLog.runtime.info("fallback notification authorization requested")
            AlarmDebugConsole.write("fallback notification authorization requested")
            let granted = try await center.requestAuthorization(options: [.alert])
            AlarmLog.runtime.info("fallback notification authorization result=\(granted)")
            AlarmDebugConsole.write("fallback notification authorization result=\(granted)")
            try await schedule(configuration: configuration)
        } catch {
            AlarmLog.runtime.error("fallback notification scheduling failed: \(error.localizedDescription, privacy: .public)")
            AlarmDebugConsole.write("fallback notification scheduling failed reason=\(error.localizedDescription)")
            // Fallback scheduling is best-effort; UI state is owned by AlarmGuardController.
        }
    }

    func schedule(configuration: AlarmConfiguration) async throws {
        let descriptors = AlarmNotificationPlan(configuration: configuration).descriptors
        let obsoleteDiagnosticIdentifiers = obsoleteDiagnosticPhaseIDs.map(AlarmNotificationPlan.identifier(forPhaseID:))
        center.removePendingNotificationRequests(withIdentifiers: descriptors.map(\.identifier) + obsoleteDiagnosticIdentifiers)
        AlarmDebugConsole.write("fallback notification removed obsolete diagnostic ids=\(obsoleteDiagnosticIdentifiers.count)")

        for descriptor in descriptors {
            let content = UNMutableNotificationContent()
            content.title = descriptor.title
            content.body = descriptor.body
            content.sound = nil

            var components = DateComponents()
            components.hour = descriptor.hour
            components.minute = descriptor.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: descriptor.identifier, content: content, trigger: trigger)
            try await center.add(request)
            AlarmLog.runtime.info("fallback notification scheduled \(descriptor.identifier, privacy: .public) \(descriptor.hour):\(descriptor.minute)")
            AlarmDebugConsole.write("fallback notification scheduled id=\(descriptor.identifier) at=\(String(format: "%02d:%02d", descriptor.hour, descriptor.minute))")
        }
    }
}
