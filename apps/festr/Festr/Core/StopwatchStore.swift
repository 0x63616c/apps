import Foundation

enum StopwatchAction: Sendable {
    case start, stop, lap, reset
}

/// All writers run on the app's main actor, including LiveActivityIntent.perform().
/// Read before every mutation so a newly constructed store never overwrites newer state.
@MainActor
final class StopwatchStore {
    static let appGroup = "group.com.calumwebb.festr"
    static let storageKey = "stopwatch.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func load() -> Stopwatch {
        guard let data = defaults.data(forKey: Self.storageKey),
              let timer = try? JSONDecoder().decode(Stopwatch.self, from: data) else { return Stopwatch() }
        return timer
    }

    @discardableResult
    func apply(_ action: StopwatchAction, at now: Date) throws -> Stopwatch {
        var timer = load()
        switch action {
        case .start: timer.start(at: now)
        case .stop: timer.stop(at: now)
        case .lap: timer.lap(at: now)
        case .reset: timer.reset()
        }
        defaults.set(try JSONEncoder().encode(timer), forKey: Self.storageKey)
        return timer
    }
}
