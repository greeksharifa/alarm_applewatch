import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Wake Guard") {
                    LabeledContent("Watch schedule", value: "07:40 / 07:50 / 08:00")
                    LabeledContent("Mode", value: "Aggressive")
                    LabeledContent("Stop condition", value: "Watch charger")
                }

                Section("Install") {
                    Text("Keep the Apple Watch unlocked and wearing, then open Wake Guard on the Watch after installation.")
                }
            }
            .navigationTitle("Wake Guard")
        }
    }
}

#Preview {
    ContentView()
}
