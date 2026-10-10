import XCTest
@testable import FestrCore

enum SeedFeed {
    static func load() throws -> Feed {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Feed.decode(Data(contentsOf: root.appendingPathComponent("Festr/Resources/seed-feed.json")))
    }
}

final class ScheduleTests: XCTestCase {
    func utc(_ raw: String) -> Date { FeedCoding.parseInstant(raw)! }

    func headTrip() throws -> Festival {
        try XCTUnwrap(try SeedFeed.load().festival(id: "head-trip-2026"))
    }

    func sets(_ festival: Festival, _ artists: [String]) -> [FestivalSet] {
        artists.map { artist in festival.sets.first { $0.artist == artist }! }
    }

    func testSeedFeedShape() throws {
        let feed = try SeedFeed.load()
        XCTAssertEqual(feed.schemaVersion, 1)
        let f = try headTrip()
        XCTAssertEqual(f.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(f.venue, "Empire Polo Club")
        XCTAssertEqual(f.sets.count, 11)
        XCTAssertEqual(f.sets(on: LocalDate("2026-10-10")!).count, 5)
        XCTAssertEqual(f.sets(on: LocalDate("2026-10-11")!).count, 6)
        XCTAssertEqual(f.stages(on: LocalDate("2026-10-10")!).map(\.name), ["Main Stage", "Sunflower Sound System"])
        XCTAssertEqual(Set(f.sets.filter(\.isOpenEnded).map(\.artist)), ["Calvin Harris", "Swedish House Mafia"])
        XCTAssertEqual(f.sourceURL?.absoluteString, "https://lineupscout.com/head-trip")
        for festival in feed.festivals {
            XCTAssertNotNil(TimeZone(identifier: festival.timeZoneIdentifier))
            XCTAssertLessThanOrEqual(festival.startDate, festival.endDate)
            for set in festival.sets {
                XCTAssertNotNil(festival.stage(id: set.stageId), "\(set.id) has a known stage")
                if let end = set.end { XCTAssertGreaterThan(end, set.start, set.id) }
            }
        }
    }

    func testFeedRoundTripsThroughTheSchema() throws {
        let feed = try SeedFeed.load()
        let decoded = try Feed.decode(try feed.encoded())
        XCTAssertEqual(decoded, feed)
        let json = String(decoding: try feed.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains("\"timeZone\" : \"America/Los_Angeles\""))
        XCTAssertTrue(json.contains("\"end\" : null"), "open ends are an explicit null")
    }

    func testRejectsNewerSchemaAndUnknownTimeZones() {
        let newer = #"{"schemaVersion":2,"generatedAt":"2026-10-10T00:00:00Z","festivals":[]}"#
        XCTAssertThrowsError(try Feed.decode(Data(newer.utf8))) { error in
            XCTAssertEqual(error as? FeedError, .unsupportedSchema(2))
        }
        let badZone = #"{"schemaVersion":1,"generatedAt":"2026-10-10T00:00:00Z","festivals":[{"id":"x","name":"X","city":"Y","timeZone":"Mars/Base","startDate":"2026-10-10","endDate":"2026-10-10","updatedAt":"2026-10-10T00:00:00Z"}]}"#
        XCTAssertThrowsError(try Feed.decode(Data(badZone.utf8)))
    }

    func testAcceptsFractionalSecondsAndMissingOptionalFields() throws {
        let raw = #"{"schemaVersion":1,"generatedAt":"2026-10-10T00:00:00.250Z","festivals":[{"id":"x","name":"X","city":"Y","timeZone":"America/Chicago","startDate":"2026-11-01","endDate":"2026-11-02","updatedAt":"2026-10-10T00:00:00Z","sets":[{"id":"s","artist":"A","stageId":"main","start":"2026-11-02T01:00:00-05:00","end":null,"updatedAt":"2026-10-10T00:00:00Z"}]}]}"#
        let feed = try Feed.decode(Data(raw.utf8))
        let festival = try XCTUnwrap(feed.festivals.first)
        XCTAssertEqual(festival.lineup, [])
        XCTAssertEqual(festival.sets.first?.start, utc("2026-11-02T06:00:00Z"))
        XCTAssertEqual(festival.day(of: festival.sets[0]), LocalDate("2026-11-01"), "01:00 local belongs to the night before")
    }

    func testClashes() throws {
        let f = try headTrip()
        let picks = sets(f, ["Seth Troxler b2b Ben Sterling", "Peggy Gou b2b Four Tet", "Under Construction (FISHER + Chris Lake)"])
        XCTAssertTrue(Clashes.ids(in: picks).isEmpty, "back-to-back sets with a gap do not clash")

        let sunflower = f.sets(on: LocalDate("2026-10-10")!).first { $0.stageId == "sunflower" }!
        let clashing = Clashes.ids(in: picks + [sunflower])
        XCTAssertEqual(clashing.count, 4)
        XCTAssertEqual(Clashes.conflicts(of: sunflower, with: picks).count, 3)
    }

    func testTouchingSetsDoNotClash() throws {
        let f = try headTrip()
        // DJ Harvey ends at 17:00 exactly when The Blessed Madonna starts.
        XCTAssertTrue(Clashes.ids(in: sets(f, ["DJ Harvey", "The Blessed Madonna"])).isEmpty)
    }

    func testOpenEndedSetsClashWithinTheAssumedDuration() throws {
        let f = try headTrip()
        let calvin = sets(f, ["Calvin Harris"])[0]
        let soon = FestivalSet(id: "soon", artist: "Soon", stageId: "main", start: calvin.start.addingTimeInterval(60 * 60), end: calvin.start.addingTimeInterval(2 * 60 * 60), updatedAt: calvin.start)
        let later = FestivalSet(id: "later", artist: "Later", stageId: "main", start: calvin.start.addingTimeInterval(91 * 60), end: calvin.start.addingTimeInterval(3 * 60 * 60), updatedAt: calvin.start)
        XCTAssertEqual(Clashes.ids(in: [calvin, soon]), ["soon", calvin.id])
        XCTAssertTrue(Clashes.ids(in: [calvin, later]).isEmpty)
    }

    func testLivePlanFollowsTheChosenSets() throws {
        let f = try headTrip()
        let saturday = LocalDate("2026-10-10")!
        let picks = sets(f, ["Seth Troxler b2b Ben Sterling", "Peggy Gou b2b Four Tet", "Under Construction (FISHER + Chris Lake)", "Calvin Harris", "DJ Harvey"])
        let plan = LivePlan(festival: f, day: saturday, sets: picks)
        XCTAssertEqual(plan.sets.count, 4, "other days are ignored")

        let duringPeggy = utc("2026-10-11T03:05:00Z") // 20:05 local
        let content = plan.content(at: duringPeggy)
        XCTAssertEqual(content.current?.artist, "Peggy Gou b2b Four Tet")
        XCTAssertEqual(content.current?.stage, "Main Stage")
        XCTAssertEqual(content.next?.artist, "Under Construction (FISHER + Chris Lake)")
        XCTAssertEqual(content.remainingAfterNext, 1)
        XCTAssertEqual(plan.staleDate(at: duringPeggy), utc("2026-10-11T03:50:00Z"))

        let inGap = plan.content(at: utc("2026-10-11T03:55:00Z"))
        XCTAssertNil(inGap.current)
        XCTAssertEqual(inGap.next?.artist, "Under Construction (FISHER + Chris Lake)")

        let closing = plan.content(at: utc("2026-10-11T07:00:00Z")) // 00:00 local, Calvin open-ended
        XCTAssertEqual(closing.current?.artist, "Calvin Harris")
        XCTAssertEqual(closing.current?.isOpenEnded, true)
        XCTAssertNil(closing.next)

        XCTAssertFalse(plan.isOver(at: utc("2026-10-11T07:29:00Z")))
        XCTAssertTrue(plan.isOver(at: utc("2026-10-11T07:30:00Z")))
    }

    func testLivePlanStaysInsideTheEightHourLimit() throws {
        let f = try headTrip()
        let saturday = LocalDate("2026-10-10")!
        // Full lineup: 15:00 to 00:30 is 9.5 hours, longer than an activity may run.
        let plan = LivePlan(festival: f, day: saturday, sets: f.sets)
        let from = try XCTUnwrap(plan.autoStartFrom)
        let lastEnd = try XCTUnwrap(plan.lastEnd)
        XCTAssertEqual(lastEnd, utc("2026-10-11T07:30:00Z"))
        XCTAssertLessThanOrEqual(lastEnd.timeIntervalSince(from), LivePlan.activityLimit)
        XCTAssertEqual(from, utc("2026-10-10T23:45:00Z"), "16:45 local")
        XCTAssertFalse(plan.shouldAutoStart(at: utc("2026-10-10T22:30:00Z")))
        XCTAssertTrue(plan.shouldAutoStart(at: from))
        XCTAssertFalse(plan.shouldAutoStart(at: lastEnd))

        // A short evening starts an hour before the first set.
        let short = LivePlan(festival: f, day: saturday, sets: sets(f, ["Peggy Gou b2b Four Tet"]))
        XCTAssertEqual(short.autoStartFrom, utc("2026-10-11T01:20:00Z"))
    }

    func testChangePointsAreUniqueAndSorted() throws {
        let f = try headTrip()
        let plan = LivePlan(festival: f, day: LocalDate("2026-10-11")!, sets: sets(f, ["DJ Harvey", "The Blessed Madonna"]))
        XCTAssertEqual(plan.changePoints(after: utc("2026-10-11T20:00:00Z")), [utc("2026-10-11T22:30:00Z"), utc("2026-10-12T00:00:00Z"), utc("2026-10-12T01:30:00Z")])
    }
}
