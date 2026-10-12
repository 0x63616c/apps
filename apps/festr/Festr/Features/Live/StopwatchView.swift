import SwiftUI

struct StopwatchView: View {
    @State private var stopwatch = StopwatchController.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StopwatchElapsedText(timer: stopwatch.timer.summary)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityIdentifier("stopwatchElapsed")
                    HStack {
                        Button(stopwatch.timer.isRunning ? "Stop" : "Start") {
                            perform(stopwatch.timer.isRunning ? .stop : .start)
                        }
                        .accessibilityIdentifier("stopwatchStartStop")
                        Spacer()
                        Button("Lap") { perform(.lap) }
                            .disabled(!stopwatch.timer.isRunning)
                            .accessibilityIdentifier("stopwatchLap")
                        Spacer()
                        Button("Reset") { perform(.reset) }
                            .disabled(!stopwatch.timer.hasStarted)
                            .accessibilityIdentifier("stopwatchReset")
                    }
                    .buttonStyle(.bordered)
                }
                if let message = errorMessage ?? stopwatch.message {
                    Text(message).font(.footnote)
                }
                if !stopwatch.timer.laps.isEmpty {
                    Section("Laps") {
                        ForEach(stopwatch.timer.laps.reversed()) { lap in
                            HStack {
                                Text("Lap \(lap.id)")
                                Spacer()
                                Text(StopwatchSummary.formatted(lap.duration)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Stopwatch")
        }
        .onAppear { stopwatch.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { stopwatch.reload() }
        }
    }

    private func perform(_ action: StopwatchAction) {
        Task {
            do {
                try await stopwatch.perform(action)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't save the stopwatch."
            }
        }
    }
}
