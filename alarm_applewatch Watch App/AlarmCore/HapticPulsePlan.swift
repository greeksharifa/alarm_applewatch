import Foundation

public struct HapticPulsePlan: Equatable, Sendable {
    public let durationSeconds: Int
    public let intervalSeconds: Double

    public init(durationSeconds: Int, intervalSeconds: Double = 1) {
        self.durationSeconds = max(0, durationSeconds)
        self.intervalSeconds = max(1, intervalSeconds)
    }

    public var pulseOffsets: [Double] {
        guard durationSeconds > 0 else {
            return []
        }

        return Array(stride(from: 0, to: Double(durationSeconds), by: intervalSeconds))
    }

    public var tailDelaySeconds: Double {
        guard let lastOffset = pulseOffsets.last else {
            return 0
        }

        return max(0, Double(durationSeconds) - lastOffset)
    }
}
