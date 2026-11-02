#if os(iOS)
import Foundation
import UserNotifications
import BlockrCore

/// Local notifications only. The same requests are safe to install from either process.
enum LockNotificationCenter {
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func schedule(_ lock: Lock) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            center.getDeliveredNotifications { delivered in
                // Check storage again after async permission/settings callbacks: installation may have failed.
                guard let state = try? Storage.read(),
                      state.receipts.contains(where: { $0.lockID == lock.id && $0.hasInstalledCoverage }) else { return }
                for notice in LockNotifications.plan(for: lock, now: Date()) {
                    guard !delivered.contains(where: { $0.request.identifier == notice.id }) else { continue }
                    if notice.fireDate == nil && !claim(notice.id) { continue }
                    add(notice, center: center)
                }
            }
        }
    }

    static func ended(_ lock: Lock) {
        // An early system callback must not announce an unlock before its absolute end.
        guard lock.end <= Date() else { return }
        let center = UNUserNotificationCenter.current()
        let notice = LockNotifications.unlocked(for: lock)
        guard claim(notice.id) else { return }
        center.getDeliveredNotifications { delivered in
            guard !delivered.contains(where: { $0.request.identifier == notice.id }) else { return }
            // Replaces the pending .end request; never create a second identifier for this boundary.
            add(notice, center: center)
        }
    }

    static func cancel(_ lock: Lock) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: LockNotifications.identifiers(for: lock))
    }

    /// Coordinated storage prevents the app and monitor from both posting an immediate start.
    private static func claim(_ id: String) -> Bool {
        (try? Storage.update { state -> Bool in
            guard !(state.immediateNotificationIDs ?? []).contains(id) else { return false }
            state.immediateNotificationIDs = (state.immediateNotificationIDs ?? []) + [id]
            return true
        }) ?? false
    }

    private static func add(_ notice: LockNotifications.Notice, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        let trigger: UNNotificationTrigger?
        if let date = notice.fireDate {
            guard date > Date() else { return }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            components.timeZone = calendar.timeZone
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else { trigger = nil }
        center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger))
    }
}
#endif
