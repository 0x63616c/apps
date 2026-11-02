import XCTest
@testable import BlockrCore

final class RestoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func lock(duration: Int = 3600) throws -> Lock {
        try Lock(group: Group(name: "Fixture", revision: Revision(1, device: "test")),
                 start: now, duration: duration, origin: "test")
    }
    func plan(_ lock: Lock, coverage: Coverage = .active, snapshot: Bool = true,
              monitored: Bool = false, authorization: Restore.Authorization = .approved,
              at date: Date? = nil, appliedAt: Date? = nil) -> [Restore.Action] {
        Restore.plan(locks: [lock], receipts: [Receipt(lockID: lock.id, coverage: coverage,
            acknowledged: now, appliedAt: appliedAt)], snapshotsPresent: snapshot ? [lock.id] : [],
            monitoredIDs: monitored ? [lock.id] : [], authorization: authorization, now: date ?? now)
    }
    func testPersistentStoreIdentity() {
        XCTAssertEqual(Restore.managedSettingsStoreName, "blockr")
    }
    func testMissingMonitorReappliesAndReschedulesInstalledCoverage() throws {
        let lock = try lock()
        for coverage in [Coverage.active, .partial] {
            XCTAssertEqual(plan(lock, coverage: coverage), [.reapply(lock.id), .reschedule(lock)])
        }
        XCTAssertEqual(plan(lock, coverage: .pending, appliedAt: now), [.reapply(lock.id), .reschedule(lock)])
    }
    func testExistingMonitorOnlyReappliesShields() throws {
        let lock = try lock()
        XCTAssertEqual(plan(lock, monitored: true), [.reapply(lock.id)])
    }
    func testExpiredAndFutureLocksAreNotRestored() throws {
        let lock = try lock()
        XCTAssertEqual(plan(lock, at: lock.end), [])
        XCTAssertEqual(plan(lock, at: now.addingTimeInterval(-1)), [])
    }
    func testNotDeterminedIsNotRevocation() throws {
        let lock = try lock()
        XCTAssertEqual(plan(lock, authorization: .notDetermined), [.reapply(lock.id), .reschedule(lock)])
    }
    func testDeniedOrMissingSnapshotIsNotProtected() throws {
        let lock = try lock()
        XCTAssertEqual(plan(lock, authorization: .denied), [.notProtected(lock.id)])
        XCTAssertEqual(plan(lock, snapshot: false), [.notProtected(lock.id)])
    }
    func testRestoreNeverExtendsEvenWithLessThanFifteenMinutesRemaining() throws {
        let lock = try lock()
        let actions = plan(lock, at: lock.end.addingTimeInterval(-30))
        XCTAssertEqual(actions, [.reapply(lock.id), .reschedule(lock)])
        guard case .reschedule(let original)? = actions.last else { return XCTFail("Missing schedule") }
        let components = try Scheduling.components(start: original.start, end: original.end)
        XCTAssertEqual(components.start.calendar?.date(from: components.start), lock.start)
        XCTAssertEqual(components.end.calendar?.date(from: components.end), lock.end)
    }
    func testUninstalledReceiptsDoNotInventCoverage() throws {
        let lock = try lock()
        for coverage in [Coverage.pending, .failed, .interrupted, .completed] {
            XCTAssertEqual(plan(lock, coverage: coverage), [])
        }
    }
    func testOverlapRestoresOnlyStillLiveLocks() throws {
        let short = try lock(duration: 900), long = try lock()
        let actions = Restore.plan(locks: [short, long], receipts: [short, long].map {
            Receipt(lockID: $0.id, coverage: .active, acknowledged: now)
        }, snapshotsPresent: [short.id, long.id], monitoredIDs: [], authorization: .approved,
           now: short.end)
        XCTAssertEqual(actions, [.reapply(long.id), .reschedule(long)])
    }
}
