import Foundation
import Combine
import HealthKit
import OSLog

@MainActor
final class WorkoutBackgroundAnchor: NSObject, ObservableObject {
    enum AnchorState: Equatable {
        case idle
        case requestingAuthorization
        case running
        case degraded(String)
    }

    @Published private(set) var state: AnchorState = .idle

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var endingSessions: [HKWorkoutSession] = []
    private var endingBuilders: [HKLiveWorkoutBuilder] = []

    var statusText: String {
        switch state {
        case .idle:
            return "Workout anchor: Idle"
        case .requestingAuthorization:
            return "Workout anchor: Requesting HealthKit"
        case .running:
            return "Workout anchor: Running"
        case .degraded(let message):
            return "Workout anchor: Degraded - \(message)"
        }
    }

    func startOrRecover() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .degraded("HealthKit unavailable")
            AlarmLog.runtime.error("workout anchor unavailable: HealthKit unavailable")
            AlarmDebugConsole.write("workout anchor degraded reason=HealthKit unavailable")
            return
        }

        if let session, session.state == .running {
            state = .running
            AlarmLog.runtime.info("workout anchor already running")
            AlarmDebugConsole.write("workout anchor already running")
            return
        }

        if await recoverActiveSession() {
            state = .running
            AlarmLog.runtime.info("workout anchor recovered active session")
            AlarmDebugConsole.write("workout anchor recovered active session")
            return
        }

        await requestAuthorizationAndStart()
    }

    func stop() {
        let sessionToEnd = session
        let builderToEnd = builder
        let shouldLogStop = sessionToEnd != nil || builderToEnd != nil || state == .running

        if shouldLogStop {
            AlarmLog.runtime.info("workout anchor stop requested")
            AlarmDebugConsole.write("workout anchor stop requested")
        }

        if let sessionToEnd {
            endingSessions.append(sessionToEnd)
            sessionToEnd.end()
        }

        if let builderToEnd {
            endingBuilders.append(builderToEnd)
            builderToEnd.endCollection(withEnd: Date()) { [weak self, builderToEnd] _, _ in
                builderToEnd.discardWorkout()
                Task { @MainActor in
                    self?.endingBuilders.removeAll { $0 === builderToEnd }
                }
            }
        }

        session = nil
        builder = nil
        state = .idle

        if shouldLogStop {
            AlarmDebugConsole.write("workout anchor state=idle")
        }
    }

    private func requestAuthorizationAndStart() async {
        state = .requestingAuthorization
        let workoutType = HKObjectType.workoutType()

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.requestAuthorization(toShare: [workoutType], read: []) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AnchorError.authorizationDenied)
                    }
                }
            }

            try await startNewSession()
            state = .running
            AlarmLog.runtime.info("workout anchor started")
            AlarmDebugConsole.write("workout anchor started")
        } catch {
            state = .degraded(error.localizedDescription)
            AlarmLog.runtime.error("workout anchor degraded: \(error.localizedDescription, privacy: .public)")
            AlarmDebugConsole.write("workout anchor degraded reason=\(error.localizedDescription)")
        }
    }

    private func startNewSession() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .unknown

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder

        let startDate = Date()
        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)
    }

    private func recoverActiveSession() async -> Bool {
        await withCheckedContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { [weak self] recoveredSession, _ in
                guard let anchor = self, let recoveredSession else {
                    continuation.resume(returning: false)
                    return
                }

                Task { @MainActor in
                    anchor.adoptRecoveredSession(recoveredSession)
                    continuation.resume(returning: true)
                }
            }
        }
    }

    private func adoptRecoveredSession(_ recoveredSession: HKWorkoutSession) {
        let builder = recoveredSession.associatedWorkoutBuilder()
        recoveredSession.delegate = self
        builder.delegate = self
        session = recoveredSession
        self.builder = builder
    }
}

extension WorkoutBackgroundAnchor: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if toState == .running {
                state = .running
                AlarmDebugConsole.write("workout session state=running")
            } else if toState == .ended || toState == .stopped {
                endingSessions.removeAll { $0 === workoutSession }
                state = .idle
                AlarmLog.runtime.info("workout session ended state=\(toState.rawValue)")
                AlarmDebugConsole.write("workout session state=\(toState.rawValue)")
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            state = .degraded(error.localizedDescription)
            AlarmDebugConsole.write("workout session failed reason=\(error.localizedDescription)")
        }
    }
}

extension WorkoutBackgroundAnchor: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

private enum AnchorError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        "HealthKit workout permission denied"
    }
}
