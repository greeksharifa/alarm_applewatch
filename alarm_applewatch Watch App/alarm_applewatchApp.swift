//
//  alarm_applewatchApp.swift
//  alarm_applewatch Watch App
//
//  Created by You Won Jang on 6/14/26.
//

import SwiftUI
import WatchKit

@main
struct alarm_applewatch_Watch_AppApp: App {
    @WKExtensionDelegateAdaptor(ExtensionDelegate.self) private var extensionDelegate
    @StateObject private var guardController = AlarmGuardController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(guardController)
        }
    }
}
