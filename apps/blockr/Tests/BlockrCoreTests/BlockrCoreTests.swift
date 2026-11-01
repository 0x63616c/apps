import XCTest
@testable import BlockrCore

final class BlockrCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func group(_ counter: Int64 = 1, device: String = "a") -> Group { Group(name: "Social", domains: ["example.com"], revision: Revision(counter, device: device)) }
    func testPresetsAndCustomDeduplication() {
        XCTAssertEqual(Durations.sorted(custom: [5400, 7200, 5400, 0]), [3600, 5400, 7200, 14400, 86400, 259200])
        XCTAssertEqual(Durations.defaultValue, 7200)
    }
    func testDurationBoundsAndNormalization() throws {
        XCTAssertEqual(try Durations.parse(days: "", hours: "1", minutes: "30"), 5400)
        XCTAssertEqual(try Durations.parse(days: "0", hours: "0", minutes: "90"), 5400)
        XCTAssertEqual(try Durations.parse(days: "7", hours: "", minutes: ""), 604800)
        XCTAssertEqual(try Durations.parse(days: "", hours: "", minutes: "15"), 900)
        for value in ["", "-1", "1.5", "1e2", "١", String(repeating: "9", count: 100)] {
            XCTAssertThrowsError(try Durations.parse(days: "", hours: "", minutes: value))
        }
        XCTAssertThrowsError(try Durations.parse(days: "7", hours: "0", minutes: "1"))
        XCTAssertThrowsError(try Durations.parse(days: "", hours: "", minutes: "14"))
    }
    func testDaysAreElapsedSecondsAcrossDST() throws {
        let lock = try Lock(group: group(), start: now, duration: 86400, origin: "a")
        XCTAssertEqual(lock.end.timeIntervalSince(lock.start), 86400)
        XCTAssertFalse(lock.isLive(at: lock.end))
        XCTAssertFalse(lock.isLive(at: lock.start.addingTimeInterval(-1)))
        XCTAssertEqual(lock.remaining(at: lock.end.addingTimeInterval(10)), 0)
    }
    func testScheduleUTCAndMinimumCustomDuration() throws {
        let start = ISO8601DateFormatter().date(from: "2026-11-01T08:30:00Z")!
        let end = start.addingTimeInterval(3600)
        let interval = try Scheduling.components(start: start, end: end)
        XCTAssertEqual(interval.start.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(interval.start.calendar?.date(from: interval.start), start)
        XCTAssertEqual(interval.end.calendar?.date(from: interval.end), end)
        XCTAssertNoThrow(try Scheduling.components(start: start, end: start.addingTimeInterval(900)))
        XCTAssertThrowsError(try Scheduling.components(start: start, end: start.addingTimeInterval(899)))
    }
    func testNames() throws {
        XCTAssertEqual(try Validation.name("  Deep work \n"), "Deep work")
        for value in [" ", String(repeating: "a", count: 41), "a\nb"] { XCTAssertThrowsError(try Validation.name(value)) }
        XCTAssertThrowsError(try Validation.name("social", others: ["Social"]))
    }
    func testDomainValidation() throws {
        XCTAssertEqual(try Validation.domains("EXAMPLE.com.\nexample.com, www.example.org"), ["example.com", "www.example.org"])
        for value in ["https://example.com", "example.com/path", "*.example.com", "localhost", "127.0.0.1", "example.com:80", "a@b.com", "a..com", "-a.com", "a_.com", "example.com?foo", ".com"] {
            XCTAssertThrowsError(try Validation.domain(value), value)
        }
        XCTAssertThrowsError(try Validation.domains((0...50).map { "a\($0).example.com" }.joined(separator: "\n")))
        XCTAssertTrue(Validation.matches(host: "a.example.com", domain: "example.com"))
        XCTAssertFalse(Validation.matches(host: "notexample.com", domain: "example.com"))
    }
    func testNoSecondStartOrMutationDuringLock() throws {
        var replica = Replica()
        let lock = try Lock(group: group(), start: now, duration: 3600, origin: "a")
        try replica.start(lock, at: now)
        XCTAssertThrowsError(try replica.start(lock, at: now))
        XCTAssertThrowsError(try replica.requireEditable(at: now))
        XCTAssertNoThrow(try replica.requireEditable(at: lock.end))
    }
    func testMergeConcurrentMetadataAndTombstones() {
        var a = Replica(), b = Replica()
        let original = group()
        var edited = original
        edited.name = "Deep work"; edited.revision = Revision(2, device: "b")
        a.groups = [original]; b.groups = [edited]
        XCTAssertEqual(a.merging(b), b.merging(a))
        var deleted = edited; deleted.deleted = true; deleted.revision = Revision(3, device: "a")
        a.groups = [deleted]
        let merged = a.merging(b)
        XCTAssertTrue(merged.visibleGroups.isEmpty)
        XCTAssertEqual(merged.groups.count, 1)
        XCTAssertEqual(merged.merging(b), merged)
    }
    func testLogicalRevisionTieBreak() {
        XCTAssertLessThan(Revision(1, device: "a"), Revision(1, device: "b"))
        XCTAssertLessThan(Revision(1, device: "z"), Revision(2, device: "a"))
    }
    func testDurationDeletionSync() {
        var a = Replica(), b = Replica()
        a.durations = [DurationPreference(seconds: 5400, revision: Revision(1, device: "a"))]
        b.durations = [DurationPreference(seconds: 5400, revision: Revision(2, device: "b"), deleted: true)]
        XCTAssertTrue(a.merging(b).customDurations.isEmpty)
        XCTAssertEqual(a.merging(b), b.merging(a))
    }
    func testConcurrentLocksUnionAndIndependentExpiry() throws {
        var a = Replica(), b = Replica()
        let first = try Lock(group: group(), start: now, duration: 3600, origin: "a")
        let second = try Lock(group: group(), start: now, duration: 7200, origin: "b")
        a.locks = [first]; b.locks = [second]
        let merged = a.merging(b)
        XCTAssertEqual(merged, b.merging(a))
        XCTAssertEqual(merged.liveLocks(at: now).count, 2)
        XCTAssertEqual(merged.liveLocks(at: first.end).map(\.id), [second.id])
        XCTAssertTrue(merged.liveLocks(at: second.end).isEmpty)
        XCTAssertEqual(merged.merging(a), merged)
    }
    func testGroupDeletionCannotEraseLockSnapshot() throws {
        var replica = Replica()
        let snapshot = group()
        replica.locks = [try Lock(group: snapshot, start: now, duration: 3600, origin: "a")]
        var remote = Replica()
        var removed = snapshot; removed.deleted = true; removed.revision = Revision(3, device: "a")
        remote.groups = [removed]
        let merged = replica.merging(remote)
        XCTAssertEqual(merged.locks.first?.group.name, "Social")
        XCTAssertEqual(merged.liveLocks(at: now).count, 1)
    }
    func testStatsRequireReceiptsAndDeduplicateIntervals() throws {
        let first = try Lock(group: group(), start: now, duration: 3600, origin: "a")
        let second = try Lock(group: group(), start: now.addingTimeInterval(1800), duration: 3600, origin: "b")
        let later = now.addingTimeInterval(10000)
        XCTAssertEqual(Statistics(locks: [first, second], receipts: [], now: later).completed, 0)
        let receipts = [first, second].map { Receipt(lockID: $0.id, coverage: .completed, acknowledged: later) }
        let stats = Statistics(locks: [first, second], receipts: receipts, now: later)
        XCTAssertEqual(stats.timeLocked, 5400)
        XCTAssertEqual(stats.streak, 2)
        let interrupted = [receipts[0], Receipt(lockID: second.id, coverage: .interrupted, acknowledged: later)]
        XCTAssertEqual(Statistics(locks: [first, second], receipts: interrupted, now: later).streak, 0)
    }
    func testRepairCannotRestoreUnbrokenStatus() throws {
        let lock = try Lock(group: group(), start: now, duration: 3600, origin: "a")
        let receipt = Receipt(lockID: lock.id, coverage: .completed, acknowledged: lock.end, interruptionObserved: true, appliedAt: now)
        let stats = Statistics(locks: [lock], receipts: [receipt], now: lock.end)
        XCTAssertEqual(stats.streak, 0)
        XCTAssertEqual(stats.completed, 0)
    }
    func testRemoteArrivalDoesNotInventLocalProtectedTime() throws {
        let lock = try Lock(group: group(), start: now, duration: 3600, origin: "b")
        let receipt = Receipt(lockID: lock.id, coverage: .completed, acknowledged: lock.end, appliedAt: now.addingTimeInterval(1800))
        XCTAssertEqual(Statistics(locks: [lock], receipts: [receipt], now: lock.end).timeLocked, 1800)
    }
    func testSyncPayloadNeverContainsTokens() throws {
        var replica = Replica(); replica.groups = [group()]
        let data = try JSONEncoder().encode(replica)
        XCTAssertEqual(try JSONDecoder().decode(Replica.self, from: data), replica)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("selection")); XCTAssertFalse(text.contains("token")); XCTAssertFalse(text.contains("receipt"))
    }
    func testRevisionExhaustionDoesNotCrash() throws {
        var replica = Replica()
        replica.groups = [group(Int64.max)]
        XCTAssertThrowsError(try replica.nextRevision(device: "a"))
        replica.groups = [group(41)]
        XCTAssertEqual(try replica.nextRevision(device: "a").counter, 42)
    }
    func testPartialRepairCannotInventUnbrokenLock() throws {
        let lock = try Lock(group: group(), start: now, duration: 3600, origin: "a")
        let pending = Receipt(lockID: lock.id, coverage: .pending, acknowledged: now)
        let partial = pending.updating(coverage: .partial, at: now)
        let repaired = partial.updating(coverage: .active, at: now.addingTimeInterval(1800))
        let completed = repaired.updating(coverage: .completed, at: lock.end)
        XCTAssertTrue(completed.interruptionObserved)
        XCTAssertEqual(Statistics(locks: [lock], receipts: [completed], now: lock.end).completed, 0)
        XCTAssertEqual(Statistics(locks: [lock], receipts: [completed], now: lock.end).timeLocked, 0)
    }
    func testReceiptPreservesFirstApplicationAndFailureAcrossRetry() {
        let pending = Receipt(lockID: UUID(), coverage: .pending, acknowledged: now)
        let active = pending.updating(coverage: .active, at: now.addingTimeInterval(10))
        let failed = active.updating(coverage: .failed, at: now.addingTimeInterval(20))
        let repaired = failed.updating(coverage: .active, at: now.addingTimeInterval(30))
        XCTAssertTrue(repaired.interruptionObserved)
        XCTAssertEqual(repaired.appliedAt, now.addingTimeInterval(10))
        XCTAssertFalse(active.interruptionObserved)
        let legacyPartial = Receipt(lockID: UUID(), coverage: .partial, acknowledged: now)
        XCTAssertTrue(legacyPartial.updating(coverage: .active, at: now).interruptionObserved)
    }
}
