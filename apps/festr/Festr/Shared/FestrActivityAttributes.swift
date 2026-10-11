import ActivityKit
import Foundation

/// One activity per festival day. The app updates the content locally while it runs.
struct FestrActivityAttributes: ActivityAttributes {
    typealias ContentState = LiveActivityContent

    var festivalID: String
    var festivalName: String
    /// Festival day, `YYYY-MM-DD`.
    var day: String
    var dayLabel: String
    var timeZoneIdentifier: String

    var key: String { "\(festivalID)|\(day)" }
}
