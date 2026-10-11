import Foundation

/// Wall-clock stopwatch: no ticking task is needed to keep time across suspension or relaunch.
struct Stopwatch: Codable, Hashable, Sendable {
    struct Lap: Codable, Hashable, Sendable, Identifiable {
        var id: Int
        var elapsed: TimeInterval
        var duration: TimeInterval
    }

    private(set) var startedAt: Date?
    private(set) var accumulated: TimeInterval = 0
    private(set) var laps: [Lap] = []

    var isRunning: Bool { startedAt != nil }
    var hasStarted: Bool { isRunning || accumulated > 0 || !laps.isEmpty }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    mutating func start(at now: Date) {
        guard !isRunning else { return }
        startedAt = now
    }

    mutating func stop(at now: Date) {
        guard isRunning else { return }
        accumulated = elapsed(at: now)
        startedAt = nil
    }

    mutating func lap(at now: Date) {
        guard isRunning else { return }
        // A backwards clock change must not produce negative lap durations.
        let total = max(elapsed(at: now), laps.last?.elapsed ?? 0)
        laps.append(Lap(id: laps.count + 1, elapsed: total, duration: total - (laps.last?.elapsed ?? 0)))
    }

    mutating func reset() { self = Stopwatch() }

    var summary: StopwatchSummary {
        StopwatchSummary(startedAt: startedAt, accumulated: accumulated, lastLap: laps.last?.duration, lapCount: laps.count)
    }
}

/// Bounded payload for ActivityKit, regardless of the number of stored laps.
struct StopwatchSummary: Codable, Hashable, Sendable {
    var startedAt: Date?
    var accumulated: TimeInterval = 0
    var lastLap: TimeInterval?
    var lapCount: Int = 0

    var isRunning: Bool { startedAt != nil }
    var hasStarted: Bool { isRunning || accumulated > 0 || lapCount > 0 }
    var timerStart: Date? { startedAt?.addingTimeInterval(-accumulated) }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    static func formatted(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}

