import SwiftUI

struct ScheduleView: View {
    @Environment(AppModel.self) private var model
    @State private var festivalID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let festival = selectedFestival {
                        if model.scheduleFestivals.count > 1 {
                            festivalMenu(current: festival)
                        }
                        let picks = model.chosenSets(in: festival)
                        if picks.isEmpty {
                            emptyState(for: festival)
                        } else {
                            ForEach(festival.days, id: \.self) { day in
                                DaySchedule(festival: festival, day: day)
                            }
                        }
                        LiveActivityCard(festival: festival)
                    } else {
                        emptyState(for: nil)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("My Schedule")
            .navigationDestination(for: String.self) { id in
                if let festival = model.festival(id: id) { FestivalView(festival: festival) }
            }
        }
    }

    private var selectedFestival: Festival? {
        let festivals = model.scheduleFestivals
        return festivals.first { $0.id == festivalID } ?? festivals.first
    }

    private func festivalMenu(current: Festival) -> some View {
        Menu {
            ForEach(model.scheduleFestivals) { festival in
                Button(festival.name) { festivalID = festival.id }
            }
        } label: {
            HStack {
                Text(current.name).font(.headline)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityIdentifier("scheduleFestivalMenu")
    }

    private func emptyState(for festival: Festival?) -> some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                "No sets yet",
                systemImage: "music.note.list",
                description: Text(festival == nil ? "Open a festival in Discover and tap the sets you want to see." : "Tap sets in the \(festival!.name) lineup to build your day.")
            )
            if let festival {
                NavigationLink(value: festival.id) {
                    Text("Open \(festival.name) lineup")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    }
}

struct DaySchedule: View {
    @Environment(AppModel.self) private var model
    var festival: Festival
    var day: LocalDate

    var body: some View {
        let picks = model.chosenSets(in: festival, on: day)
        let clashing = Clashes.ids(in: picks)
        let clock = FestivalClock(festival)
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(clock.weekday(day)).font(.title2.weight(.bold))
                    Text(clock.monthDay(day)).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if !clashing.isEmpty {
                        Pill(text: "\(clashing.count) clashing", systemImage: "exclamationmark.triangle.fill", tint: Palette.clash)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(picks) { set in
                        ScheduleRow(set: set, festival: festival, clock: clock, clashes: clashing.contains(set.id), isLive: set.isPlaying(at: model.now()))
                        if set.id != picks.last?.id { Divider().padding(.leading, 86) }
                    }
                }
                .glassCard(cornerRadius: 24)
            }
            .accessibilityIdentifier("scheduleDay-\(day.description)")
        }
    }
}

struct ScheduleRow: View {
    @Environment(AppModel.self) private var model
    var set: FestivalSet
    var festival: Festival
    var clock: FestivalClock
    var clashes: Bool
    var isLive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(clock.time(set.start)).font(.subheadline.weight(.semibold).monospacedDigit())
                Text(set.end.map(clock.time) ?? "late").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(set.artist).font(.headline)
                HStack(spacing: 6) {
                    Text(festival.stageName(for: set))
                    if clashes {
                        Label("Clash", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.clash)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isLive { Pill(text: "Now", tint: Palette.live) }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contextMenu {
            Button("Remove from My Schedule", systemImage: "minus.circle", role: .destructive) { model.toggle(set) }
        }
    }
}

struct LiveActivityCard: View {
    @Environment(AppModel.self) private var model
    @Environment(LiveActivityController.self) private var live
    var festival: Festival
    @State private var showingPreview = false

    var body: some View {
        let now = model.now()
        let day = festival.festivalDay(at: now) ?? festival.days.first ?? festival.startDate
        let plan = live.plan(for: festival, day: day, model: model)
        let clock = FestivalClock(festival)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Activity", systemImage: "platter.filled.bottom.iphone")
                    .font(.headline)
                Spacer()
                if live.isRunning(plan) { Pill(text: "On", tint: Palette.live) }
            }
            Text(description(plan: plan, clock: clock, isToday: festival.festivalDay(at: now) != nil))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("Start automatically on festival days", isOn: Binding(get: { live.autoStart }, set: { live.setAutoStart($0) }))
                .font(.subheadline)
            if let message = live.message {
                Text(message).font(.footnote).foregroundStyle(Palette.clash)
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if live.isRunning(plan) {
                        Button("Stop", systemImage: "stop.fill") { live.stop() }
                            .buttonStyle(.glass)
                    } else {
                        Button("Start", systemImage: "play.fill") { live.start(plan, now: now) }
                            .buttonStyle(.glassProminent)
                            .disabled(festival.festivalDay(at: now) == nil || plan.isOver(at: now))
                    }
                    Button("Preview", systemImage: "eye") { showingPreview = true }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("liveActivityPreviewButton")
                }
            }
        }
        .padding(18)
        .glassCard()
        .sheet(isPresented: $showingPreview) {
            LockScreenPreview(festival: festival, plan: plan, now: now)
        }
    }

    private func description(plan: LivePlan, clock: FestivalClock, isToday: Bool) -> String {
        guard isToday else {
            return "On festival days, follow the current set, its progress and what's next from your Lock Screen and Dynamic Island."
        }
        guard let from = plan.autoStartFrom, let end = plan.lastEnd else { return "Pick some sets first." }
        if plan.isOver(at: model.now()) { return "Today's sets have finished." }
        return "Runs from \(clock.time(from)) until \(clock.time(end)). Live Activities last up to eight hours, so it starts once the rest of the day fits."
    }
}
