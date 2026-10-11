import AppIntents
import SwiftUI

struct StopwatchElapsedText: View {
    var timer: StopwatchSummary
    var referenceDate: Date? = nil

    var body: some View {
        Group {
            if let referenceDate {
                Text(StopwatchSummary.formatted(timer.elapsed(at: referenceDate)))
            } else if let start = timer.timerStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text(StopwatchSummary.formatted(timer.accumulated))
            }
        }
        .monospacedDigit()
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }
}

struct StopwatchActivityView: View {
    var timer: StopwatchSummary
    var referenceDate: Date? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                StopwatchElapsedText(timer: timer, referenceDate: referenceDate)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let lastLap = timer.lastLap {
                    Text("Last \(StopwatchSummary.formatted(lastLap))")
                }
                Text("Laps \(timer.lapCount)")
            }
            .font(.caption.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            HStack {
                if timer.isRunning {
                    Button("Stop", intent: StopStopwatchIntent())
                } else {
                    Button("Start", intent: StartStopwatchIntent())
                }
                Button("Lap", intent: LapStopwatchIntent())
                    .disabled(!timer.isRunning)
                Button("Reset", intent: ResetStopwatchIntent())
                    .disabled(!timer.hasStarted)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(referenceDate != nil)
        }
    }
}
