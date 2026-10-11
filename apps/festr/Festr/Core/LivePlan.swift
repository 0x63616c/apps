import Foundation

/// What the Live Activity shows. Shared by the app (which computes it) and the widget extension (which renders it).
/// Progress is rendered with timer-based views, so it keeps moving between local updates without push notifications.
struct LiveActivityContent: Codable, Hashable, Sendable {
    struct Slot: Codable, Hashable, Sendable {
        var artist: String
        var stage: String
        var start: Date
        var end: Date
        var isOpenEnded: Bool
    }

    var current: Slot?
    var next: Slot?
    /// Sets left after `next`, for the "+2 more" hint.
    var remainingAfterNext: Int
}

/// Plans one Live Activity per festival day. ActivityKit ends an activity after roughly eight hours,
/// so the automatic start is delayed until the remaining day fits inside that limit.
struct LivePlan: Sendable {
    static let activityLimit: TimeInterval = 8 * 60 * 60
    static let safetyMargin: TimeInterval = 15 * 60
    static let leadTime: TimeInterval = 60 * 60

    var festival: Festival
    var day: LocalDate
    /// The sets to follow, already filtered (chosen sets, or the full lineup).
    var sets: [FestivalSet]

    init(festival: Festival, day: LocalDate, sets: [FestivalSet]) {
        self.festival = festival
        self.day = day
        self.sets = sets.filter { festival.day(of: $0) == day }.sorted(by: FestivalSet.chronological)
    }

    var firstStart: Date? { sets.first?.start }
    var lastEnd: Date? { sets.map(\.effectiveEnd).max() }

    /// Earliest moment the app should start the activity on its own.
    var autoStartFrom: Date? {
        guard let firstStart, let lastEnd else { return nil }
        return max(firstStart.addingTimeInterval(-Self.leadTime), lastEnd.addingTimeInterval(-(Self.activityLimit - Self.safetyMargin)))
    }

    func shouldAutoStart(at now: Date) -> Bool {
        guard let from = autoStartFrom, let lastEnd else { return false }
        return now >= from && now < lastEnd
    }

    /// True once the last set has finished; the activity should end.
    func isOver(at now: Date) -> Bool {
        guard let lastEnd else { return true }
        return now >= lastEnd
    }

    func content(at now: Date) -> LiveActivityContent {
        let playing = sets.filter { $0.isPlaying(at: now) }
        // With overlapping picks, follow the one that started most recently.
        let current = playing.max { $0.start < $1.start }
        let upcoming = sets.filter { $0.start > now }
        return LiveActivityContent(
            current: current.map(slot),
            next: upcoming.first.map(slot),
            remainingAfterNext: max(0, upcoming.count - 1)
        )
    }

    /// Instants at which the content changes, so the app can schedule local updates.
    func changePoints(after now: Date) -> [Date] {
        let points = sets.flatMap { [$0.start, $0.effectiveEnd] }.filter { $0 > now }
        return Array(Set(points)).sorted()
    }

    /// When the shown content becomes out of date.
    func staleDate(at now: Date) -> Date? {
        changePoints(after: now).first
    }

    private func slot(_ set: FestivalSet) -> LiveActivityContent.Slot {
        .init(artist: set.artist, stage: festival.stageName(for: set), start: set.start, end: set.effectiveEnd, isOpenEnded: set.isOpenEnded)
    }
}
