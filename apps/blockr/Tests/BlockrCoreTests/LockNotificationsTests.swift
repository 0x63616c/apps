import Foundation
import XCTest
@testable import BlockrCore

final class LockNotificationsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 0)
    private let id = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private func lock(duration: Int = 900) throws -> Lock {
        let group = Group(name: "Focus", revision: Revision(1, device: "test"))
        return try Lock(id: id, group: group, start: now, duration: duration, origin: "test")
    }

    func testStableIdentifiersContentAndTimes() throws {
        let lock = try lock()
        let plan = LockNotifications.plan(for: lock, now: now, locale: Locale(identifier: "en_US_POSIX"),
                                          timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(plan.map(\.id), ["start", "soon", "end"].map { "blockr.\(id.uuidString).\($0)" })
        XCTAssertEqual(plan.map(\.id), LockNotifications.plan(for: lock, now: now.addingTimeInterval(1)).map(\.id))
        XCTAssertEqual(plan.map(\.title), ["Focus", "Focus", "Focus"])
        XCTAssertEqual(plan.map { $0.body.replacingOccurrences(of: "\u{202F}", with: " ") },
                       ["Locked for 15m · until 12:15 AM", "5m left", "Unlocked"])
        XCTAssertNil(plan[0].fireDate)
        XCTAssertEqual(plan[1].fireDate, lock.end.addingTimeInterval(-300))
        XCTAssertEqual(plan[2].fireDate, lock.end)
        XCTAssertEqual(LockNotifications.unlocked(for: lock).id, plan[2].id)
        XCTAssertEqual(LockNotifications.unlocked(for: lock).body, "Unlocked")
        XCTAssertNil(LockNotifications.unlocked(for: lock).fireDate)
    }

    func testMultiDayNotificationUsesCompactDuration() throws {
        let lock = try lock(duration: 2 * 86400 + 3 * 3600 + 15 * 60)
        let plan = LockNotifications.plan(for: lock, now: now)
        XCTAssertTrue(try XCTUnwrap(plan.first).body.hasPrefix("Locked for 2d 3h 15m · until "))
        XCTAssertEqual(plan[1].body, "5m left")
    }

    func testDifferentLocksHaveDifferentIdentifiers() throws {
        let first = try lock()
        let second = try Lock(group: first.group, start: now, duration: 900, origin: "test")
        XCTAssertTrue(Set(LockNotifications.identifiers(for: first))
            .isDisjoint(with: LockNotifications.identifiers(for: second)))
    }

    func testShortImportedLocksOmitHeadsUp() throws {
        // Local starts require 15 minutes; a decoded remote/imported lock can be shorter.
        let data = try JSONEncoder().encode(lock())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for seconds in [300, 360, 361] {
            json["end"] = now.addingTimeInterval(Double(seconds)).timeIntervalSinceReferenceDate
            let short = try JSONDecoder().decode(Lock.self, from: JSONSerialization.data(withJSONObject: json))
            let plan = LockNotifications.plan(for: short, now: now)
            XCTAssertEqual(plan.count, seconds > 360 ? 3 : 2)
        }
    }

    func testPastHeadsUpAndExpiredLocksAreSkipped() throws {
        let lock = try lock()
        for elapsed in [600, 601, 899] {
            let date = now.addingTimeInterval(Double(elapsed))
            let plan = LockNotifications.plan(for: lock, now: date)
            XCTAssertEqual(plan.map(\.id), [LockNotifications.identifiers(for: lock)[0], LockNotifications.identifiers(for: lock)[2]])
            XCTAssertTrue(plan.compactMap(\.fireDate).allSatisfy { $0 > date })
        }
        XCTAssertTrue(LockNotifications.plan(for: lock, now: lock.end).isEmpty)
        XCTAssertTrue(LockNotifications.plan(for: lock, now: lock.end.addingTimeInterval(1)).isEmpty)
    }

    func testFutureStartIsScheduledInsteadOfDeliveredImmediately() throws {
        let lock = try lock()
        XCTAssertEqual(LockNotifications.plan(for: lock, now: now.addingTimeInterval(-60)).first?.fireDate, now)
    }
}
