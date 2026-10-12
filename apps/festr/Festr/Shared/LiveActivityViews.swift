import SwiftUI

enum LiveStyle {
    static let accent = Color(white: 0.587)
    static let live = Color(white: 0.550)

    static func time(_ date: Date, zone: String) -> String {
        let timeZone = TimeZone(identifier: zone) ?? .current
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

/// Lock screen / banner presentation. Also used by the in-app preview.
struct LiveActivityLockScreenView: View {
    var attributes: FestrActivityAttributes
    var state: LiveActivityContent
    /// Fixed moment for previews; live presentations leave this nil and use timer-driven views.
    var referenceDate: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: state.stopwatch == nil ? 10 : 6) {
            HStack {
                Text(attributes.festivalName)
                    .font(.caption.weight(.semibold))
                if !attributes.isStopwatch {
                    Text("· \(attributes.dayLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: attributes.isStopwatch ? "stopwatch" : "music.note")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiveStyle.accent)
            }

            if state.stopwatch != nil {
                compactSchedule
            } else {
                if let current = state.current {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("NOW")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(LiveStyle.live)
                            Text(current.artist)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        SetProgress(slot: current, referenceDate: referenceDate)
                        HStack {
                            Text(current.stage)
                            Spacer()
                            Text(current.isOpenEnded ? "till late" : "until \(LiveStyle.time(current.end, zone: attributes.timeZoneIdentifier))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else if state.next == nil, !attributes.isStopwatch {
                    Text("That's a wrap for today.")
                        .font(.headline)
                }

                if let next = state.next {
                    HStack(spacing: 6) {
                        Text(state.current == nil ? "UP NEXT" : "NEXT")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(LiveStyle.accent)
                        Text(next.artist)
                            .font(state.current == nil ? .headline : .subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(LiveStyle.time(next.start, zone: attributes.timeZoneIdentifier))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    HStack {
                        Text(next.stage)
                        Spacer()
                        if state.current == nil, let referenceDate {
                            Text("starts in \(Duration.seconds(max(0, next.start.timeIntervalSince(referenceDate))).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                        } else if state.current == nil {
                            Text("starts in \(Text(timerInterval: Date.now...max(Date.now, next.start), countsDown: true))")
                                .monospacedDigit()
                        } else if state.remainingAfterNext > 0 {
                            Text("+\(state.remainingAfterNext) more")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if let stopwatch = state.stopwatch {
                StopwatchActivityView(timer: stopwatch, referenceDate: referenceDate)
            }
        }
        .padding(state.stopwatch == nil ? 16 : 12)
    }

    // Two compact set rows leave room for the controls within the Lock Screen banner.
    private var compactSchedule: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let current = state.current {
                setRow("NOW", slot: current, time: current.isOpenEnded ? "late" : LiveStyle.time(current.end, zone: attributes.timeZoneIdentifier))
            }
            if let next = state.next {
                setRow("NEXT", slot: next, time: LiveStyle.time(next.start, zone: attributes.timeZoneIdentifier))
            }
            if state.current == nil, state.next == nil, !attributes.isStopwatch {
                Text("That's a wrap for today.").font(.caption)
            }
        }
    }

    private func setRow(_ label: String, slot: LiveActivityContent.Slot, time: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.caption2.weight(.heavy)).foregroundStyle(LiveStyle.accent)
            Text(slot.artist).fontWeight(.semibold)
            Text(slot.stage).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(time).monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
    }
}

/// Timer-driven, so it advances on its own between updates.
struct SetProgress: View {
    var slot: LiveActivityContent.Slot
    var referenceDate: Date? = nil

    var body: some View {
        if let referenceDate {
            let total = max(60, slot.end.timeIntervalSince(slot.start))
            ProgressView(value: min(max(referenceDate.timeIntervalSince(slot.start) / total, 0), 1))
                .progressViewStyle(.linear)
                .tint(LiveStyle.accent)
        } else {
            timerProgress
        }
    }

    private var timerProgress: some View {
        ProgressView(timerInterval: slot.start...max(slot.start.addingTimeInterval(60), slot.end), countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(LiveStyle.accent)
    }
}

struct LiveActivityCompactTrailing: View {
    var state: LiveActivityContent

    var body: some View {
        if let stopwatch = state.stopwatch, stopwatch.hasStarted {
            StopwatchElapsedText(timer: stopwatch)
                .frame(width: 52)
        } else if let current = state.current, !current.isOpenEnded {
            Text(timerInterval: Date.now...max(Date.now, current.end), countsDown: true)
                .monospacedDigit()
                .frame(maxWidth: 52)
                .foregroundStyle(LiveStyle.accent)
        } else if let next = state.next {
            Text(timerInterval: Date.now...max(Date.now, next.start), countsDown: true)
                .monospacedDigit()
                .frame(maxWidth: 52)
        } else {
            Image(systemName: "checkmark")
        }
    }
}
