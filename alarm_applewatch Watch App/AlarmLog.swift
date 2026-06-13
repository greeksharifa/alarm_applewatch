import Foundation
import OSLog

enum AlarmLog {
    static let runtime = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.local.alarm-applewatch.watchkitapp",
        category: "WakeGuard"
    )
}

enum AlarmDebugConsole {
    static func write(_ message: String) {
        #if DEBUG
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "WakeGuard \(timestamp) \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
        #endif
    }
}
