import Foundation
import Combine
import WatchKit

@MainActor
final class BatteryStopMonitor: ObservableObject {
    @Published private(set) var state: AlarmBatteryState = .unknown

    private var lastLoggedState: AlarmBatteryState?

    init() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        refresh()
    }

    var shouldStopCurrentPhase: Bool {
        BatteryStopPolicy.shouldStop(for: state)
    }

    func refresh() {
        state = AlarmBatteryState(deviceState: WKInterfaceDevice.current().batteryState)
        if lastLoggedState != state {
            lastLoggedState = state
            AlarmDebugConsole.write("battery state=\(state)")
        }
    }

    var statusText: String {
        switch state {
        case .unknown:
            return "Battery: Unknown"
        case .unplugged:
            return "Battery: Not charging"
        case .charging:
            return "Battery: Charging"
        case .full:
            return "Battery: Full"
        }
    }
}

private extension AlarmBatteryState {
    init(deviceState: WKInterfaceDeviceBatteryState) {
        switch deviceState {
        case .charging:
            self = .charging
        case .full:
            self = .full
        case .unplugged:
            self = .unplugged
        case .unknown:
            fallthrough
        @unknown default:
            self = .unknown
        }
    }
}
