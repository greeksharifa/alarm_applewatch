import Foundation
import WatchKit

@MainActor
final class SmartAlarmBridge: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    private var invalidatingSessions: [ObjectIdentifier: WKExtendedRuntimeSession] = [:]
    private let onEvent: (String) -> Void

    init(onEvent: @escaping (String) -> Void = { _ in }) {
        self.onEvent = onEvent
    }

    func scheduleIfActive(at date: Date) {
        guard WKExtension.shared().applicationState == .active else {
            AlarmDebugConsole.write("smart alarm bridge skipped reason=inactive")
            return
        }

        let now = Date()
        guard date > now, date.timeIntervalSince(now) <= 36 * 60 * 60 else {
            AlarmDebugConsole.write("smart alarm bridge skipped reason=outside-window")
            return
        }

        if let session {
            invalidatingSessions[ObjectIdentifier(session)] = session
            session.invalidate()
        }

        let nextSession = WKExtendedRuntimeSession()
        nextSession.delegate = self
        nextSession.start(at: date)
        session = nextSession
        AlarmDebugConsole.write("smart alarm bridge scheduled at=\(date.ISO8601Format())")
        onEvent("Smart Alarm bridge scheduled")
    }

    func notifyRunningSessionIfPossible() {
        guard session?.state == .running else {
            return
        }

        session?.notifyUser(hapticType: .notification) { _ in
            3.0
        }
    }

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        let sessionID = ObjectIdentifier(extendedRuntimeSession)
        Task { @MainActor [weak self] in
            self?.handleSessionDidStart(sessionID: sessionID)
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        let sessionID = ObjectIdentifier(extendedRuntimeSession)
        let reasonDescription = String(describing: reason)
        let errorDescription = error?.localizedDescription

        Task { @MainActor [weak self] in
            self?.handleSessionInvalidation(
                sessionID: sessionID,
                reasonDescription: reasonDescription,
                errorDescription: errorDescription
            )
        }
    }

    private func handleSessionDidStart(sessionID: ObjectIdentifier) {
        guard let session, ObjectIdentifier(session) == sessionID else {
            return
        }

        AlarmDebugConsole.write("smart alarm bridge started")
        notifyRunningSessionIfPossible()
    }

    private func handleSessionInvalidation(
        sessionID: ObjectIdentifier,
        reasonDescription: String,
        errorDescription: String?
    ) {
        invalidatingSessions.removeValue(forKey: sessionID)

        if let currentSession = session, ObjectIdentifier(currentSession) == sessionID {
            session = nil
        }

        let detail = errorDescription.map { ": \($0)" } ?? ""
        AlarmDebugConsole.write("smart alarm bridge invalidated reason=\(reasonDescription)\(detail)")
        onEvent("Smart Alarm bridge invalidated (\(reasonDescription))\(detail)")
    }
}
