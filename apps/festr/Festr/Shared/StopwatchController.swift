import ActivityKit
import Foundation
import Observation

/// LiveActivityIntent runs in the app process. The shared main-actor instance serializes
/// persistence; the task chain also keeps asynchronous ActivityKit updates in order.
@MainActor
@Observable
final class StopwatchController {
    static let shared = StopwatchController()
    private let store = StopwatchStore(defaults: UserDefaults(suiteName: StopwatchStore.appGroup)!)
    private(set) var timer = Stopwatch()
    private(set) var message: String?
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?

    private init() { reload() }

    func reload() { timer = store.load() }

    func perform(_ action: StopwatchAction) async throws {
        timer = try store.apply(action, at: Date())
        await enqueue {
            let summary = self.store.load().summary
            let activities = Activity<FestrActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
            if activities.isEmpty, summary.hasStarted, ActivityAuthorizationInfo().areActivitiesEnabled {
                do {
                    _ = try Activity<FestrActivityAttributes>.request(
                        attributes: .stopwatch,
                        content: ActivityContent(state: LiveActivityContent(current: nil, next: nil, remainingAfterNext: 0, stopwatch: summary), staleDate: nil),
                        pushType: nil
                    )
                    self.message = nil
                } catch {
                    self.message = "Couldn't start the Live Activity."
                }
            }
            for activity in activities {
                var state = activity.content.state
                state.stopwatch = summary
                let content = ActivityContent(state: state, staleDate: activity.content.staleDate)
                if activity.attributes.isStopwatch, !summary.hasStarted {
                    await activity.end(content, dismissalPolicy: .immediate)
                } else {
                    await activity.update(content)
                }
            }
        }
    }

    /// Schedule refreshes merge the latest persisted timer instead of clearing it.
    func update(_ activity: Activity<FestrActivityAttributes>, state: LiveActivityContent, staleDate: Date?, end: Bool = false) async {
        await enqueue {
            var state = state
            state.stopwatch = self.store.load().summary
            let content = ActivityContent(state: state, staleDate: staleDate)
            if end, state.stopwatch?.hasStarted != true {
                await activity.end(content, dismissalPolicy: .default)
            } else {
                await activity.update(content)
            }
        }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = pendingUpdate
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        pendingUpdate = task
        await task.value
    }
}
