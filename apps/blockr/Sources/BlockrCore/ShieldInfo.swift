import Foundation

/// Only installed, live policy metadata; opaque selections stay on this device.
public struct ShieldInfo: Codable, Equatable, Sendable {
    public let lockID: UUID
    public let groupName: String
    public let end: Date
    public let selection: Data
    public let domains: [String]

    public init(lockID: UUID, groupName: String, end: Date, selection: Data, domains: [String] = []) {
        self.lockID = lockID; self.groupName = groupName; self.end = end
        self.selection = selection; self.domains = domains
    }

    /// Prefer the latest matching expiry, then conservatively describe the latest installed expiry.
    public static func pick(_ entries: [Self], now: Date, matches: (Self) -> Bool) -> Self? {
        let live = entries.filter { $0.end > now }
        return live.filter(matches).max { $0.end < $1.end } ?? live.max { $0.end < $1.end }
    }

    public func title(now: Date) -> String {
        Durations.label(max(60, Int(ceil(max(0, end.timeIntervalSince(now)) / 60)) * 60))
    }

    public func subtitle(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return ["until " + formatter.string(from: end), groupName.isEmpty ? nil : groupName]
            .compactMap { $0 }.joined(separator: " · ")
    }

    public static let defaultsKey = "blockr.shieldInfo.v1"

    public static func read(from defaults: UserDefaults) throws -> [Self]? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try JSONDecoder().decode([Self].self, from: data)
    }

    public static func write(_ entries: [Self], to defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(entries), forKey: defaultsKey)
    }
}
