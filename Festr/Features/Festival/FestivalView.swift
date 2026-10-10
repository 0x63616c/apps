import SwiftUI

struct FestivalView: View {
    @Environment(AppModel.self) private var model
    var festival: Festival
    @State private var day: LocalDate?

    var body: some View {
        let clock = FestivalClock(festival)
        let selectedDay = day ?? defaultDay
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(clock)

                if festival.hasSetTimes {
                    DayPicker(festival: festival, selection: Binding(get: { selectedDay }, set: { day = $0 }))
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        DayTimeline(festival: festival, day: selectedDay, now: model.now())
                    }
                } else {
                    LineupList(festival: festival)
                }

                footer(clock)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(festival.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.isFavourite(festival) ? "Remove from favourites" : "Add to favourites",
                       systemImage: model.isFavourite(festival) ? "heart.fill" : "heart") {
                    model.toggleFavourite(festival)
                }
                .tint(Palette.accent)
                .accessibilityIdentifier("festivalFavourite")
            }
        }
    }

    private var defaultDay: LocalDate {
        festival.festivalDay(at: model.now()) ?? festival.days.first ?? festival.startDate
    }

    private func header(_ clock: FestivalClock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(festival.name)
                .font(.largeTitle.weight(.bold))
                .accessibilityIdentifier("festivalTitle")
            Text([festival.venue, festival.location].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(clock.dateRange(festival))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func footer(_ clock: FestivalClock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All times \(clock.zoneName()). Tap a set to add it to My Schedule.")
            Text("Times updated \(festival.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .accessibilityIdentifier("timesUpdated")
            if let source = festival.sourceURL {
                Link("Source: \(source.host() ?? source.absoluteString)", destination: source)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}

struct DayPicker: View {
    var festival: Festival
    @Binding var selection: LocalDate

    var body: some View {
        let clock = FestivalClock(festival)
        Picker("Day", selection: $selection) {
            ForEach(festival.days, id: \.self) { day in
                Text("\(clock.shortWeekday(day)) \(day.day)").tag(day)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("dayPicker")
    }
}

struct DayTimeline: View {
    @Environment(AppModel.self) private var model
    var festival: Festival
    var day: LocalDate
    var now: Date

    var body: some View {
        let sets = festival.sets(on: day)
        let chosen = model.chosenSets(in: festival, on: day)
        let clashing = Clashes.ids(in: chosen)
        let clock = FestivalClock(festival)
        VStack(spacing: 0) {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                TimelineRow(
                    set: set,
                    stage: festival.stageName(for: set),
                    clock: clock,
                    isChosen: model.isChosen(set),
                    clashesWith: clashing.contains(set.id) ? Clashes.conflicts(of: set, with: chosen).map(\.artist) : [],
                    isLive: set.isPlaying(at: now),
                    isFirst: index == 0,
                    isLast: index == sets.count - 1
                ) {
                    withAnimation(.snappy) { model.toggle(set) }
                }
            }
        }
    }
}

struct TimelineRow: View {
    var set: FestivalSet
    var stage: String
    var clock: FestivalClock
    var isChosen: Bool
    var clashesWith: [String]
    var isLive: Bool
    var isFirst: Bool
    var isLast: Bool
    var toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(clock.time(set.start))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(set.end.map(clock.time) ?? "late")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .trailing)
            .padding(.top, 16)

            rail

            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(set.artist)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(stage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !clashesWith.isEmpty {
                            Label(clashesWith.count == 1 ? "Clashes with \(clashesWith[0])" : "Clashes with \(clashesWith[0]) and \(clashesWith.count - 1) more", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.clash)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        Image(systemName: isChosen ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title2)
                            .foregroundStyle(isChosen ? Palette.accent : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                        if isLive {
                            Pill(text: "Now", tint: Palette.live)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .glassCard(cornerRadius: 20, tint: isChosen ? Palette.accent.opacity(0.22) : nil, interactive: true)
            .overlay {
                if !clashesWith.isEmpty {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.clash.opacity(0.8), lineWidth: 1.5)
                }
            }
            .padding(.vertical, 5)
            .accessibilityIdentifier("set-\(set.id)")
            .accessibilityValue(isChosen ? (clashesWith.isEmpty ? "In My Schedule" : "In My Schedule, clashing") : "Not in My Schedule")
            .accessibilityHint(isChosen ? "Removes from My Schedule" : "Adds to My Schedule")
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.secondary.opacity(isFirst ? 0 : 0.25)).frame(width: 2, height: 18)
            Circle()
                .fill(isLive ? Palette.live : (isChosen ? Palette.accent : Color.secondary.opacity(0.5)))
                .frame(width: 10, height: 10)
            Rectangle().fill(Color.secondary.opacity(isLast ? 0 : 0.25)).frame(width: 2)
        }
        .frame(width: 10)
    }
}

struct LineupList: View {
    var festival: Festival

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Set times haven't been published yet.", systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if festival.lineup.isEmpty {
                Text("Lineup to be announced.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Lineup")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(festival.lineup, id: \.self) { artist in
                        Text(artist)
                            .font(.body)
                        if artist != festival.lineup.last { Divider() }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
        }
        .accessibilityIdentifier("lineupList")
    }
}
