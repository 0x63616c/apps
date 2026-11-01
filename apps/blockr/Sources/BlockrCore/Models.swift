import Foundation

public enum BlockrError: Error, LocalizedError, Equatable {
    case invalidName, duplicateName, invalidDomain(String), tooManyDomains, invalidDuration, emptySelection, locked, unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .invalidName: "Use a group name from 1 to 40 characters."
        case .duplicateName: "A group with this name already exists."
        case .invalidDomain(let value): "Enter a hostname, such as example.com: \(value)"
        case .tooManyDomains: "Use at most 50 websites."
        case .invalidDuration: "Choose 15 minutes to 7 days, using whole numbers."
        case .emptySelection: "Pick apps, categories or websites on this device."
        case .locked: "Changes are locked until this lock ends."
        case .unavailable(let reason): reason
        }
    }
}

public enum Durations {
    public static let presets = [3600, 7200, 14400, 86400, 259200]
    public static let defaultValue = 7200
    public static func parse(days: String, hours: String, minutes: String) throws -> Int {
        let fields = [days, hours, minutes]
        guard fields.contains(where: { !$0.isEmpty }) else { throw BlockrError.invalidDuration }
        let values = try fields.map { field -> Int in
            if field.isEmpty { return 0 }
            guard field.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(field), value <= 10080 else { throw BlockrError.invalidDuration }
            return value
        }
        let seconds = values[0] * 86400 + values[1] * 3600 + values[2] * 60
        guard (900...604800).contains(seconds) else { throw BlockrError.invalidDuration }
        return seconds
    }
    public static func sorted(custom: [Int]) -> [Int] { Array(Set(presets + custom.filter { (900...604800).contains($0) })).sorted() }
    public static func label(_ seconds: Int) -> String {
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        return [(days, "d"), (hours, "h"), (minutes, "m")].filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }
}

public enum Validation {
    public static func name(_ value: String, others: [String] = []) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(value.count), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw BlockrError.invalidName }
        guard !others.contains(where: { $0.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { throw BlockrError.duplicateName }
        return value
    }
    public static func domain(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix(".") { value.removeLast() }
        guard !value.contains(":"), !value.contains("/"), !value.contains("@"), !value.contains("*"), !value.contains("?"), !value.contains("#"),
              let host = URL(string: "https://\(value)")?.host, host.contains("."), host.count <= 253 else { throw BlockrError.invalidDomain(input) }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ part in
            !part.isEmpty && part.count <= 63 && part.first != "-" && part.last != "-" && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }), !parts.allSatisfy({ Int($0) != nil }) else { throw BlockrError.invalidDomain(input) }
        return host
    }
    public static func domains(_ text: String) throws -> [String] {
        let values = try text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map { try domain(String($0)) }
        let result = Array(Set(values)).sorted()
        guard result.count <= 50 else { throw BlockrError.tooManyDomains }
        return result
    }
    public static func matches(host: String, domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
}

/// Logical revision avoids trusting device wall clocks for concurrent metadata edits.
public struct Revision: Codable, Equatable, Comparable, Sendable {
    public var counter: Int64
    public var device: String
    public init(_ counter: Int64, device: String) { self.counter = counter; self.device = device }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.counter == rhs.counter ? lhs.device < rhs.device : lhs.counter < rhs.counter }
}
public struct Group: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var domains: [String]
    public var categoryIntent: String
    public var requiresLocalSelection: Bool
    public var revision: Revision
    public var deleted: Bool
    public init(id: UUID = UUID(), name: String, domains: [String] = [], categoryIntent: String = "", requiresLocalSelection: Bool = false, revision: Revision, deleted: Bool = false) {
        self.id = id; self.name = name; self.domains = domains; self.categoryIntent = categoryIntent; self.requiresLocalSelection = requiresLocalSelection; self.revision = revision; self.deleted = deleted
    }
}
public struct DurationPreference: Codable, Equatable, Sendable {
    public var seconds: Int
    public var revision: Revision
    public var deleted: Bool
    public init(seconds: Int, revision: Revision, deleted: Bool = false) { self.seconds = seconds; self.revision = revision; self.deleted = deleted }
}
public struct Lock: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let group: Group
    public let start: Date
    public let end: Date
    public let origin: String
    public init(id: UUID = UUID(), group: Group, start: Date, duration: Int, origin: String) throws {
        guard (900...604800).contains(duration) else { throw BlockrError.invalidDuration }
        self.id = id; self.group = group; self.start = start; self.end = start.addingTimeInterval(Double(duration)); self.origin = origin
    }
    public func isLive(at now: Date) -> Bool { start <= now && end > now }
    public func remaining(at now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }
}
public enum Coverage: String, Codable, Sendable { case pending, active, partial, interrupted, completed, failed }
public struct Receipt: Codable, Equatable, Sendable {
    public var lockID: UUID
    public var coverage: Coverage
    public var acknowledged: Date
    public init(lockID: UUID, coverage: Coverage, acknowledged: Date) { self.lockID = lockID; self.coverage = coverage; self.acknowledged = acknowledged }
}
public struct Replica: Codable, Equatable, Sendable {
    public var groups: [Group] = []
    public var durations: [DurationPreference] = []
    public var locks: [Lock] = []
    public init() {}
    public var visibleGroups: [Group] { groups.filter { !$0.deleted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    public var customDurations: [Int] { durations.filter { !$0.deleted }.map(\.seconds) }
    public func liveLocks(at now: Date) -> [Lock] { locks.filter { $0.isLive(at: now) }.sorted { $0.end < $1.end } }
    public func nextRevision(device: String) -> Revision { Revision(max(groups.map(\.revision.counter).max() ?? 0, durations.map(\.revision.counter).max() ?? 0) + 1, device: device) }
    public mutating func requireEditable(at now: Date) throws { guard liveLocks(at: now).isEmpty else { throw BlockrError.locked } }
    public mutating func start(_ lock: Lock, at now: Date) throws {
        try requireEditable(at: now)
        guard lock.isLive(at: now) else { throw BlockrError.invalidDuration }
        locks.append(lock)
    }
    /// Tombstones survive indefinitely. Immutable lock union never accepts an edited session.
    public func merging(_ remote: Replica) -> Replica {
        var result = self
        for group in remote.groups {
            if let i = result.groups.firstIndex(where: { $0.id == group.id }) {
                if result.groups[i].revision < group.revision { result.groups[i] = group }
            } else { result.groups.append(group) }
        }
        for preference in remote.durations where (900...604800).contains(preference.seconds) && !Durations.presets.contains(preference.seconds) {
            if let i = result.durations.firstIndex(where: { $0.seconds == preference.seconds }) {
                if result.durations[i].revision < preference.revision { result.durations[i] = preference }
            } else { result.durations.append(preference) }
        }
        for lock in remote.locks where !result.locks.contains(where: { $0.id == lock.id }) && lock.end > lock.start && lock.end.timeIntervalSince(lock.start) <= 604800 { result.locks.append(lock) }
        result.groups.sort { $0.id.uuidString < $1.id.uuidString }
        result.durations.sort { $0.seconds < $1.seconds }
        result.locks.sort { $0.id.uuidString < $1.id.uuidString }
        return result
    }
}

public struct Statistics: Equatable, Sendable {
    public let completed: Int
    public let streak: Int
    public let timeLocked: TimeInterval
    public init(locks: [Lock], receipts: [Receipt], now: Date) {
        let ended = locks.filter { $0.end <= now }.sorted { $0.end < $1.end }
        let successful = ended.filter { lock in receipts.contains { $0.lockID == lock.id && $0.coverage == .completed } }
        completed = successful.count
        // Union intervals so concurrent locks do not double-count time.
        var seconds: TimeInterval = 0, lastEnd = Date.distantPast
        for lock in successful.sorted(by: { $0.start < $1.start }) {
            seconds += max(0, lock.end.timeIntervalSince(max(lastEnd, lock.start)))
            lastEnd = max(lastEnd, lock.end)
        }
        timeLocked = seconds
        var count = 0
        for lock in ended.reversed() {
            guard successful.contains(where: { $0.id == lock.id }) else { break }
            count += 1
        }
        streak = count
    }
}
