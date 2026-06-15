//
//  ContentView.swift
//  alarm_applewatch Watch App
//
//  Created by You Won Jang on 6/14/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var guardController: AlarmGuardController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Wake Guard")
                    .font(.headline)

                Toggle(
                    "Morning Guard",
                    isOn: Binding(
                        get: { guardController.isAggressiveModeEnabled },
                        set: { guardController.setAggressiveModeEnabled($0) }
                    )
                )
                .disabled(guardController.currentPhaseText.hasPrefix("Running") || guardController.isManualHapticTestRunning)

                Button {
                    guardController.runManualHapticTest()
                } label: {
                    Text(guardController.isManualHapticTestRunning ? "Testing..." : "Test Haptics")
                }
                .disabled(!guardController.canRunManualHapticTest)

                Divider()

                statusRow("Schedule", guardController.scheduleText)
                statusRow("Next", guardController.nextPhaseText.replacingOccurrences(of: "Next: ", with: ""))
                statusRow("Phase", guardController.currentPhaseText)
                statusRow("Battery", guardController.batteryMonitor.statusText.replacingOccurrences(of: "Battery: ", with: ""))
                statusRow("Anchor", guardController.workoutAnchor.statusText.replacingOccurrences(of: "Workout anchor: ", with: ""))

                Divider()

                Text("Place Apple Watch on charger to stop the current haptic phase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(guardController.lastEventText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }
}
