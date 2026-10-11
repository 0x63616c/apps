import Foundation
import XCTest
@testable import ShotsCore

final class LibraryPresentationTests: XCTestCase {
    func testHiddenStateMigrationAndRoundTripPreservesAssignments() throws {
        let tag = UUID()
        let record = Screenshot(id: "one", createdAt: .distantPast, addedTagIDs: [tag])
        let data = try JSONEncoder().encode(record)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "hiddenAt")
        var restored = try JSONDecoder().decode(Screenshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.hiddenAt)
        restored.hiddenAt = Date(timeIntervalSince1970: 1234)
        let hidden = try JSONDecoder().decode(Screenshot.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(hidden.hiddenAt, restored.hiddenAt)
        XCTAssertEqual(hidden.addedTagIDs, [tag])
        restored.hiddenAt = nil
        XCTAssertEqual(restored, record)
    }

    func testGroupingUsesLocalCalendarDaysAcrossDSTAndSortsNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let formatter = ISO8601DateFormatter()
        let samples = ["2026-03-08T09:30:00Z", "2026-03-08T10:30:00Z", "2026-03-08T07:30:00Z"]
            .enumerated().map { Screenshot(id: "\($0.offset)", createdAt: formatter.date(from: $0.element)!) }
        let groups = ScreenshotDay.groups(samples, calendar: calendar)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].screenshots.map(\.id), ["1", "0"])
        XCTAssertEqual(groups[1].screenshots.map(\.id), ["2"])
    }

    func testTimingEstimateWaitsForSamplesAndStopsAtCompletion() {
        var timing = ScanMeasurement()
        timing.completed = 2
        XCTAssertNil(timing.estimatedRemaining(total: 10, elapsed: 4))
        timing.completed = 3
        XCTAssertEqual(timing.estimatedRemaining(total: 10, elapsed: 6), 14)
        XCTAssertNil(timing.estimatedRemaining(total: 3, elapsed: 6))
        XCTAssertEqual(ScanMeasurement.duration(125), "2m 5s")
    }

    func testLargeLibraryGroupingKeepsAllIDsAndOrdersDaysAndItems() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let newestDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_442_000))
        // Exactly 1,000 days of 15 unique records, deliberately oldest-first.
        let samples = (0..<15_000).reversed().map { index in
            Screenshot(id: "large-\(index)", createdAt: newestDay.addingTimeInterval(
                -Double(index / 15) * 86_400 + Double(15 - index % 15) * 60))
        }
        let groups = ScreenshotDay.groups(samples, calendar: calendar)
        XCTAssertEqual(groups.count, 1_000)
        XCTAssertEqual(groups.first?.id, newestDay)
        XCTAssertTrue(groups.allSatisfy { $0.screenshots.count == 15 })
        XCTAssertTrue(zip(groups, groups.dropFirst()).allSatisfy { $0.id > $1.id })
        for group in groups {
            XCTAssertTrue(group.screenshots.allSatisfy { calendar.startOfDay(for: $0.createdAt) == group.id })
            XCTAssertTrue(zip(group.screenshots, group.screenshots.dropFirst()).allSatisfy { $0.createdAt > $1.createdAt })
        }
        let flattenedIDs = groups.flatMap { $0.screenshots.map(\.id) }
        XCTAssertEqual(flattenedIDs.count, 15_000)
        XCTAssertEqual(Set(flattenedIDs), Set(samples.map(\.id)))
        XCTAssertEqual(groups.first?.screenshots.map(\.id), (0..<15).map { "large-\($0)" })
        XCTAssertEqual(groups.last?.screenshots.last?.id, "large-14999")
    }

    func testLargeLibraryGroupingPerformance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let samples = (0..<15_000).map { index in
            Screenshot(id: "large-\(index)", createdAt: Date(timeIntervalSince1970: 1_790_442_000 - Double(index * 60)))
        }
        // Record a baseline without machine-dependent elapsed-time pass/fail limits.
        measure {
            let groups = ScreenshotDay.groups(samples, calendar: calendar)
            XCTAssertEqual(groups.reduce(0) { $0 + $1.screenshots.count }, 15_000)
        }
    }
}
