import Foundation

public enum AggressiveModePreference {
    public static func resolve(storedValue: Bool?, forceEnabled: Bool) -> Bool {
        if forceEnabled {
            return true
        }

        return storedValue ?? true
    }
}
