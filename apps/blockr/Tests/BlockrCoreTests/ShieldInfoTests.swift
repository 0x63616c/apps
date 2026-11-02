import Foundation
import XCTest
@testable import BlockrCore

final class ShieldInfoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 0)
    private func info(_ seconds: TimeInterval, name: String = "Focus") -> ShieldInfo {
        ShieldInfo(lockID: UUID(), groupName: name, end: now.addingTimeInterval(seconds),
                   selection: Data([1, 2, 3]), domains: ["example.com"])
    }

    func testJSONRoundTrip() throws {
        let entries = [info(3600)]
        XCTAssertEqual(try JSONDecoder().decode([ShieldInfo].self, from: JSONEncoder().encode(entries)), entries)
    }

    func testMatchingEntryWinsOverLaterUnrelatedEntry() {
        let matching = info(900), later = info(7200)
        XCTAssertEqual(ShieldInfo.pick([later, matching], now: now) { $0.lockID == matching.lockID }, matching)
    }

    func testLatestMatchingEntryWins() {
        let early = info(900), late = info(7200)
        XCTAssertEqual(ShieldInfo.pick([late, early], now: now) { _ in true }, late)
    }

    func testUnknownTokenFallsBackToLatestLiveExpiry() {
        let early = info(900), late = info(7200), expired = info(-1)
        XCTAssertEqual(ShieldInfo.pick([late, expired, early], now: now) { _ in false }, late)
    }

    func testExpiredMatchIsIgnoredAndOnlyEmptyOrExpiredReturnsNil() {
        let expired = info(-1), boundary = info(0), live = info(60)
        XCTAssertEqual(ShieldInfo.pick([expired, boundary, live], now: now) { $0.lockID == expired.lockID }, live)
        XCTAssertNil(ShieldInfo.pick([], now: now) { _ in true })
        XCTAssertNil(ShieldInfo.pick([expired, boundary], now: now) { _ in true })
    }

    func testCompactDataPathUsesDefaultsWithoutStateFileOrCoordination() throws {
        let suite = "BlockrCoreTests.ShieldInfo.\(UUID().uuidString)"
        let writer = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { writer.removePersistentDomain(forName: suite) }
        let reader = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertNil(try ShieldInfo.read(from: reader))
        let entries = [info(3600)]
        try ShieldInfo.write(entries, to: writer)
        XCTAssertEqual(try ShieldInfo.read(from: reader), entries)
        try ShieldInfo.write([], to: writer)
        XCTAssertEqual(try ShieldInfo.read(from: reader), [])
    }

    func testMinimalTitleAndSubtitleWithInjectedLocaleAndTimeZone() {
        let entry = info(4800)
        XCTAssertEqual(entry.title(now: now), "1h 20m")
        XCTAssertEqual(info(1).title(now: now), "1m")
        let locale = Locale(identifier: "en_US_POSIX")
        let utc = TimeZone(secondsFromGMT: 0)!
        // ICU may use a narrow no-break space before AM; normalize only that locale detail.
        XCTAssertEqual(entry.subtitle(locale: locale, timeZone: utc)
            .replacingOccurrences(of: "\u{202F}", with: " "), "until 1:20 AM · Focus")
        XCTAssertEqual(info(4800, name: "").subtitle(locale: locale, timeZone: utc)
            .replacingOccurrences(of: "\u{202F}", with: " "), "until 1:20 AM")
    }
}
