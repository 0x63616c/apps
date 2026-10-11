import ActivityKit
import Foundation
import Observation

/// Starts, updates and ends the festival-day Live Activity. There are no push updates: the app
/// refreshes the content whenever it runs, and timer-based views keep progress moving in between.
@MainActor
@Observable
final class LiveActivityController {
    private(set) var activeKey: String?
    private(set) var message: String?
    private(set) var autoStart: Bool

    private let defaults: UserDefaults
    private static let autoStartKey = "liveActivityAutoStart"
    private static let stoppedKey = "liveActivityStoppedDay"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoStart = defaults.object(forKey: Self.autoStartKey) as? Bool ?? true
    }

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private var activities: [Activity<FestrActivityAttributes>] { Activity<FestrActivityAttributes>.activities }

    func setAutoStart(_ value: Bool) {
        autoStart = value
        defaults.set(value, forKey: Self.autoStartKey)
    }

    func restore() {
        activeKey = activities.first {
            !$0.attributes.isStopwatch && ($0.activityState == .active || $0.activityState == .stale)
        }?.attributes.key
    }

    /// Today's plan: the festival happening now that has chosen sets, otherwise a favourite's full lineup.
    func todaysPlan(model: AppModel) -> LivePlan? {
        let now = model.now()
        let candidates = model.scheduleFestivals + model.upcomingFestivals.filter { model.isFavourite($0) }
        for festival in candidates {
            guard let day = festival.festivalDay(at: now) else { continue }
            let chosen = model.chosenSets(in: festival, on: day)
            let sets = chosen.isEmpty ? festival.sets(on: day) : chosen
            guard !sets.isEmpty else { continue }
            return LivePlan(festival: festival, day: day, sets: sets)
        }
        return nil
    }

    func plan(for festival: Festival, day: LocalDate, model: AppModel) -> LivePlan {
        let chosen = model.chosenSets(in: festival, on: day)
        return LivePlan(festival: festival, day: day, sets: chosen.isEmpty ? festival.sets(on: day) : chosen)
    }

    func isRunning(_ plan: LivePlan) -> Bool {
        activeKey == Self.key(plan)
    }

    func start(_ plan: LivePlan, now: Date) {
        guard areActivitiesEnabled else {
            message = "Live Activities are turned off for Festr in Settings."
            return
        }
        guard !plan.isOver(at: now) else {
            message = "The last set has finished."
            return
        }
        let key = Self.key(plan)
        if let existing = activities.first(where: { $0.attributes.key == key && ($0.activityState == .active || $0.activityState == .stale) }) {
            endOtherActivities(keeping: key)
            activeKey = key
            update(existing, plan: plan, now: now)
            return
        }
        let attributes = FestrActivityAttributes(
            festivalID: plan.festival.id,
            festivalName: plan.festival.name,
            day: plan.day.description,
            dayLabel: FestivalClock(plan.festival).weekday(plan.day),
            timeZoneIdentifier: plan.festival.timeZoneIdentifier
        )
        do {
            StopwatchController.shared.reload()
            var state = plan.content(at: now)
            state.stopwatch = StopwatchController.shared.timer.summary
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: plan.staleDate(at: now)),
                pushType: nil
            )
            endOtherActivities(keeping: key)
            activeKey = key
            message = nil
            defaults.removeObject(forKey: Self.stoppedKey)
        } catch {
            message = "Couldn't start the Live Activity."
        }
    }

    func stop() {
        if let activeKey { defaults.set(activeKey, forKey: Self.stoppedKey) }
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activeKey = nil
    }

    /// Called every 30 seconds while the app is active.
    func tick(model: AppModel) {
        guard !model.environment.isScreenshotMode else { return }
        let now = model.now()
        for activity in activities {
            guard !activity.attributes.isStopwatch else { continue }
            let key = activity.attributes.key
            guard let festival = model.festival(id: activity.attributes.festivalID),
                  let day = LocalDate(activity.attributes.day) else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                continue
            }
            let dayPlan = plan(for: festival, day: day, model: model)
            if dayPlan.isOver(at: now) {
                Task {
                    await StopwatchController.shared.update(activity, state: dayPlan.content(at: now), staleDate: nil, end: true)
                }
                if activeKey == key { activeKey = nil }
            } else {
                update(activity, plan: dayPlan, now: now)
            }
        }
        restore()

        guard autoStart, activeKey == nil, let plan = todaysPlan(model: model),
              plan.shouldAutoStart(at: now),
              defaults.string(forKey: Self.stoppedKey) != Self.key(plan) else { return }
        start(plan, now: now)
    }

    private func update(_ activity: Activity<FestrActivityAttributes>, plan: LivePlan, now: Date) {
        Task {
            await StopwatchController.shared.update(activity, state: plan.content(at: now), staleDate: plan.staleDate(at: now))
        }
    }

    private static func key(_ plan: LivePlan) -> String { "\(plan.festival.id)|\(plan.day.description)" }

    private func endOtherActivities(keeping key: String) {
        // Keep the stopwatch visible if requesting its replacement fails.
        for activity in activities where activity.attributes.key != key {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
