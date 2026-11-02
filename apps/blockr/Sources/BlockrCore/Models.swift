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
    /// Compact whole minutes, omitting zero components (and empty below one minute).
    public static func label(_ seconds: Int) -> String {
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        return [(days, "d"), (hours, "h"), (minutes, "m")].filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }

    /// Timer style below a day; compact days/hours/minutes from one day onward.
    /// Remaining time rounds up, elapsed time down: to seconds below a day,
    /// to minutes at/above a day. Rounding seconds can promote 86399.5 remaining
    /// seconds to "1d". Zero and negative intervals display "0:00".
    public static func clock(_ seconds: TimeInterval, remaining: Bool = false) -> String {
        let interval = max(0, seconds)
        let wholeSeconds = Int(remaining ? ceil(interval) : floor(interval))
        if wholeSeconds >= 86400 {
            let minutes = Int(remaining ? ceil(interval / 60) : floor(interval / 60))
            return label(minutes * 60)
        }
        let hours = wholeSeconds / 3600
        let minutes = wholeSeconds % 3600 / 60
        let seconds = wholeSeconds % 60
        let tail = String(format: "%02d", seconds)
        return hours > 0 ? "\(hours):\(String(format: "%02d", minutes)):\(tail)" : "\(minutes):\(tail)"
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
    public var interruptionObserved: Bool
    public var appliedAt: Date?
    public var installationID: UUID?
    public init(lockID: UUID, coverage: Coverage, acknowledged: Date, interruptionObserved: Bool = false, appliedAt: Date? = nil, installationID: UUID? = nil) {
        self.lockID = lockID; self.coverage = coverage; self.acknowledged = acknowledged
        self.interruptionObserved = interruptionObserved; self.appliedAt = appliedAt; self.installationID = installationID
    }
    /// Reserve under coordinated storage before calling the external monitoring service.
    public static func beginInstallation(lockID: UUID, previous: Receipt?, id: UUID, at now: Date) throws -> Receipt {
        guard previous?.coverage != .pending, previous?.coverage != .active else { throw BlockrError.locked }
        return Receipt(lockID: lockID, coverage: .pending, acknowledged: now,
            interruptionObserved: previous?.interruptionObserved == true || previous.map { [.partial, .failed, .interrupted].contains($0.coverage) } == true,
            appliedAt: previous?.appliedAt, installationID: id)
    }
    public var hasInstalledCoverage: Bool {
        [.active, .partial].contains(coverage) || (coverage == .pending && appliedAt != nil)
    }
    /// Expiry of a startup lease permits crash recovery without racing a live initial call.
    public func installationNeedsRecovery(at now: Date) -> Bool {
        coverage == .pending && now.timeIntervalSince(acknowledged) >= 60
    }
    /// Once coverage is incomplete, a later repair cannot establish uninterrupted protection.
    public func updating(coverage: Coverage, at now: Date) -> Receipt {
        Receipt(lockID: lockID, coverage: coverage, acknowledged: now,
            interruptionObserved: interruptionObserved || [.partial, .failed, .interrupted].contains(self.coverage) || [.partial, .failed, .interrupted].contains(coverage),
            appliedAt: appliedAt ?? ([.active, .partial].contains(coverage) ? now : nil), installationID: installationID)
    }
}
public struct Replica: Codable, Equatable, Sendable {
    public var groups: [Group] = []
    public var durations: [DurationPreference] = []
    public var locks: [Lock] = []
    public init() {}
    public var visibleGroups: [Group] { groups.filter { !$0.deleted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    public var customDurations: [Int] { durations.filter { !$0.deleted }.map(\.seconds) }
    public func liveLocks(at now: Date) -> [Lock] { locks.filter { $0.isLive(at: now) }.sorted { $0.end < $1.end } }
    /// A shield describes the latest relevant session actually installed on this device.
    /// The caller matches opaque local selections without exporting them into the replica.
    public func shieldLock(at now: Date, receipts: [Receipt], matches: (Lock) -> Bool) -> Lock? {
        liveLocks(at: now).last { lock in
            receipts.contains { $0.lockID == lock.id && $0.hasInstalledCoverage } && matches(lock)
        }
    }
    public func nextRevision(device: String) throws -> Revision {
        let counter = max(groups.map(\.revision.counter).max() ?? 0, durations.map(\.revision.counter).max() ?? 0)
        guard counter < Int64.max else { throw BlockrError.unavailable("Sync revision limit reached. Changes could not be saved.") }
        return Revision(counter + 1, device: device)
    }
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
        let successful = ended.filter { lock in receipts.contains { $0.lockID == lock.id && $0.coverage == .completed && !$0.interruptionObserved } }
        completed = successful.count
        timeLocked = Self.lockedSeconds(locks: locks, receipts: receipts, at: now)
        var count = 0
        for lock in ended.reversed() {
            guard successful.contains(where: { $0.id == lock.id }) else { break }
            count += 1
        }
        streak = count
    }
    /// Completed protection plus elapsed installed protection, with overlaps counted once.
    public static func lockedSeconds(locks: [Lock], receipts: [Receipt], at now: Date) -> TimeInterval {
        let intervals = locks.compactMap { lock -> (start: Date, end: Date)? in
            guard let receipt = receipts.first(where: { $0.lockID == lock.id }),
                  !receipt.interruptionObserved,
                  (lock.end <= now && receipt.coverage == .completed)
                    || (lock.isLive(at: now) && receipt.hasInstalledCoverage) else { return nil }
            let start = max(lock.start, receipt.appliedAt ?? lock.start)
            let end = min(lock.end, now)
            return start < end ? (start, end) : nil
        }.sorted { $0.start < $1.start }
        var seconds: TimeInterval = 0, lastEnd = Date.distantPast
        for interval in intervals {
            seconds += max(0, interval.end.timeIntervalSince(max(lastEnd, interval.start)))
            lastEnd = max(lastEnd, interval.end)
        }
        return seconds
    }
}

/// UTC calendar components preserve elapsed-duration schedules across DST folds and timezone changes.
public enum Scheduling {
    public static func components(start: Date, end: Date) throws -> (start: DateComponents, end: DateComponents) {
        guard (900...604800).contains(end.timeIntervalSince(start)) else { throw BlockrError.invalidDuration }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func components(_ date: Date) -> DateComponents {
            var result = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
            result.calendar = calendar; result.timeZone = calendar.timeZone
            return result
        }
        return (components(start), components(end))
    }
}
