import Foundation

public enum AlarmBatteryState: Equatable, Sendable {
    case unknown
    case unplugged
    case charging
    case full
}

public enum BatteryStopPolicy {
    public static func shouldStop(for state: AlarmBatteryState) -> Bool {
        state == .charging || state == .full
    }
}
