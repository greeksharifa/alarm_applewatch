import UserNotifications
import WatchKit

final class ExtensionDelegate: NSObject, WKExtensionDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        AlarmGuardController.shared.bootstrap()
    }

    func applicationDidBecomeActive() {
        AlarmGuardController.shared.bootstrap()
    }

    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        AlarmGuardController.shared.handleExtendedRuntimeSession(extendedRuntimeSession)
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }
}
