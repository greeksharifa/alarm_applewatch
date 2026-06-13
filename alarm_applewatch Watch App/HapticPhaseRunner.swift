import Foundation
import OSLog
import WatchKit

@MainActor
final class HapticPhaseRunner {
    private let device: WKInterfaceDevice

    init(device: WKInterfaceDevice = .current()) {
        self.device = device
    }

    func run(phase: AlarmPhase, shouldCancel: @escaping @MainActor () -> Bool) async -> HapticPhaseResult {
        let plan = HapticPulsePlan(durationSeconds: phase.durationSeconds)
        var deliveredPulses = 0
        var previousOffset: Double = 0

        for offset in plan.pulseOffsets {
            if Task.isCancelled {
                return HapticPhaseResult(phase: phase, deliveredPulses: deliveredPulses, endReason: .cancelled)
            }

            if shouldCancel() {
                return HapticPhaseResult(phase: phase, deliveredPulses: deliveredPulses, endReason: .chargingDetected)
            }

            await sleep(seconds: max(0, offset - previousOffset))
            previousOffset = offset

            device.play(.notification)
            deliveredPulses += 1
            AlarmLog.runtime.info("haptic pulse phase=\(phase.id, privacy: .public) pulse=\(deliveredPulses)")
            AlarmDebugConsole.write("haptic pulse phase=\(phase.id) pulse=\(deliveredPulses)")
        }

        if plan.tailDelaySeconds > 0 {
            await sleep(seconds: plan.tailDelaySeconds)
        }

        if Task.isCancelled {
            return HapticPhaseResult(phase: phase, deliveredPulses: deliveredPulses, endReason: .cancelled)
        }

        if shouldCancel() {
            return HapticPhaseResult(phase: phase, deliveredPulses: deliveredPulses, endReason: .chargingDetected)
        }

        return HapticPhaseResult(phase: phase, deliveredPulses: deliveredPulses, endReason: .completed)
    }

    private func sleep(seconds: Double) async {
        guard seconds > 0 else {
            return
        }

        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

struct HapticPhaseResult: Equatable {
    enum EndReason: Equatable {
        case completed
        case chargingDetected
        case cancelled
    }

    let phase: AlarmPhase
    let deliveredPulses: Int
    let endReason: EndReason
}
