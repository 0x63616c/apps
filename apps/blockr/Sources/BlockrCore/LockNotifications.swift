import Foundation

public enum LockNotifications {
    public struct Notice: Equatable, Sendable {
        public let id: String
        public let title: String
        public let body: String
        /// nil means deliver immediately.
        public let fireDate: Date?
    }

    public static func identifiers(for lock: Lock) -> [String] {
        ["start", "soon", "end"].map { "blockr.\(lock.id.uuidString).\($0)" }
    }

    public static func unlocked(for lock: Lock) -> Notice {
        Notice(id: identifiers(for: lock)[2], title: lock.group.name, body: "Unlocked", fireDate: nil)
    }

    public static func plan(for lock: Lock, now: Date, locale: Locale = .current,
                            timeZone: TimeZone = .current) -> [Notice] {
        guard lock.end > now else { return [] }
        let ids = identifiers(for: lock)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        var result = [Notice(id: ids[0], title: lock.group.name,
                             body: "Locked for \(Durations.label(Int(lock.end.timeIntervalSince(lock.start)))) · until \(formatter.string(from: lock.end))",
                             fireDate: lock.start > now ? lock.start : nil)]
        let soon = lock.end.addingTimeInterval(-300)
        if lock.end.timeIntervalSince(lock.start) > 360 && soon > now {
            result.append(Notice(id: ids[1], title: lock.group.name, body: "\(Durations.label(300)) left", fireDate: soon))
        }
        result.append(Notice(id: ids[2], title: lock.group.name, body: "Unlocked", fireDate: lock.end))
        return result
    }
}
