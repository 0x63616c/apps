import XCTest
@testable import FestrCore

final class TimeTests: XCTestCase {
    let la = TimeZone(identifier: "America/Los_Angeles")!
    let ny = TimeZone(identifier: "America/New_York")!

    func utc(_ raw: String) -> Date { FeedCoding.parseInstant(raw)! }

    func festival(timeZone: String = "America/Los_Angeles", start: String = "2026-10-10", end: String = "2026-10-11", sets: [FestivalSet] = []) -> Festival {
        Festival(id: "test", name: "Test", venue: "Field", city: "Indio", region: "CA", timeZoneIdentifier: timeZone,
                 startDate: LocalDate(start)!, endDate: LocalDate(end)!, updatedAt: utc("2026-10-01T00:00:00Z"),
                 stages: [Stage(id: "main", name: "Main Stage")], sets: sets)
    }

    func set(_ id: String, _ start: String, _ end: String?, day: String? = nil) -> FestivalSet {
        FestivalSet(id: id, artist: id, stageId: "main", day: day.flatMap(LocalDate.init), start: utc(start), end: end.map(utc), updatedAt: utc("2026-10-01T00:00:00Z"))
    }

    /// ICU uses a narrow no-break space before AM/PM on newer platforms.
    func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    func testLocalDateParsingAndArithmetic() {
        XCTAssertEqual(LocalDate("2026-10-10"), LocalDate(year: 2026, month: 10, day: 10))
        XCTAssertNil(LocalDate("2026-13-01"))
        XCTAssertNil(LocalDate("10/10/2026"))
        XCTAssertEqual(LocalDate("2026-10-31")!.adding(days: 1), LocalDate("2026-11-01"))
        XCTAssertEqual(LocalDate("2026-12-31")!.adding(days: 1), LocalDate("2027-01-01"))
        XCTAssertEqual(LocalDate("2026-10-10")!.days(until: LocalDate("2026-11-08")!), 29)
        XCTAssertEqual(LocalDate("2026-10-10")!.weekday, 7)
    }

    func testLocalDateOfAnInstantDependsOnTheFestivalTimeZone() {
        let instant = utc("2026-10-11T05:00:00Z")
        XCTAssertEqual(LocalDate(instant, in: la), LocalDate("2026-10-10"))
        XCTAssertEqual(LocalDate(instant, in: ny), LocalDate("2026-10-11"))
    }

    func testSetsAfterMidnightBelongToThePreviousFestivalDay() {
        // 00:30 local on Sunday, with no explicit day, is still Saturday night.
        let lateNight = set("late", "2026-10-11T07:30:00Z", "2026-10-11T09:00:00Z")
        let afternoon = set("afternoon", "2026-10-11T22:00:00Z", "2026-10-11T23:00:00Z")
        let f = festival(sets: [lateNight, afternoon])
        XCTAssertEqual(f.day(of: lateNight), LocalDate("2026-10-10"))
        XCTAssertEqual(f.day(of: afternoon), LocalDate("2026-10-11"))
        XCTAssertEqual(f.sets(on: LocalDate("2026-10-10")!).map(\.id), ["late"])
        XCTAssertEqual(f.days, [LocalDate("2026-10-10")!, LocalDate("2026-10-11")!])
    }

    func testExplicitDayWins() {
        let early = set("early", "2026-10-11T13:00:00Z", "2026-10-11T14:00:00Z", day: "2026-10-10")
        XCTAssertEqual(festival(sets: [early]).day(of: early), LocalDate("2026-10-10"))
    }

    func testFestivalDayAtNowRollsOverAtSixAM() {
        let f = festival()
        XCTAssertEqual(f.festivalDay(at: utc("2026-10-11T08:00:00Z")), LocalDate("2026-10-10"), "01:00 Sunday local is Saturday night")
        XCTAssertEqual(f.festivalDay(at: utc("2026-10-11T14:00:00Z")), LocalDate("2026-10-11"))
        XCTAssertNil(f.festivalDay(at: utc("2026-10-12T14:00:00Z")))
    }

    func testSetRunningPastMidnight() throws {
        let feed = try SeedFeed.load()
        let headTrip = try XCTUnwrap(feed.festival(id: "head-trip-2026"))
        let saturday = LocalDate("2026-10-10")!
        let sunflower = try XCTUnwrap(headTrip.sets(on: saturday).first { $0.stageId == "sunflower" })
        XCTAssertEqual(sunflower.start, utc("2026-10-10T22:00:00Z"))
        XCTAssertEqual(sunflower.end, utc("2026-10-11T07:30:00Z"), "00:30 is the next calendar day")
        XCTAssertEqual(headTrip.day(of: sunflower), saturday)
        XCTAssertTrue(sunflower.isPlaying(at: utc("2026-10-11T07:15:00Z")), "00:15 Sunday local")
        XCTAssertFalse(sunflower.isPlaying(at: utc("2026-10-11T07:30:00Z")))
        let clock = FestivalClock(timeZone: headTrip.timeZone, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(plain(clock.range(sunflower)), "3:00 PM – 12:30 AM")
    }

    func testOpenEndedCloser() throws {
        let headTrip = try XCTUnwrap(try SeedFeed.load().festival(id: "head-trip-2026"))
        let calvin = try XCTUnwrap(headTrip.sets.first { $0.artist == "Calvin Harris" })
        XCTAssertNil(calvin.end)
        XCTAssertTrue(calvin.isOpenEnded)
        XCTAssertEqual(calvin.start, utc("2026-10-11T06:00:00Z"))
        XCTAssertEqual(calvin.effectiveEnd, utc("2026-10-11T07:30:00Z"))
        XCTAssertEqual(headTrip.day(of: calvin), LocalDate("2026-10-10"))
        let clock = FestivalClock(timeZone: headTrip.timeZone, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(plain(clock.range(calvin)), "11:00 PM – late")
    }

    func testTimesAreShownInTheFestivalTimeZoneNotTheDevice() {
        let start = utc("2026-10-10T23:30:00Z")
        XCTAssertEqual(plain(FestivalClock(timeZone: la, locale: Locale(identifier: "en_US")).time(start)), "4:30 PM")
        XCTAssertEqual(plain(FestivalClock(timeZone: ny, locale: Locale(identifier: "en_US")).time(start)), "7:30 PM")
    }

    func testDaylightSavingEndsDuringALateSet() {
        // Clocks go back at 02:00 on Nov 1 2026 in New York, so 22:00 -> 02:00 lasts five hours.
        let f = festival(timeZone: "America/New_York", start: "2026-10-31", end: "2026-10-31")
        let start = LocalDate("2026-10-31")!.at(hour: 22, minute: 0, in: ny)
        let end = LocalDate("2026-11-01")!.at(hour: 2, minute: 0, in: ny)
        XCTAssertEqual(end.timeIntervalSince(start), 5 * 60 * 60)
        let late = FestivalSet(id: "late", artist: "Late", stageId: "main", start: start, end: end, updatedAt: start)
        XCTAssertEqual(f.day(of: late), LocalDate("2026-10-31"))
    }

    func testDaysUntilUsesTheFestivalCalendar() {
        let f = festival()
        // 23:30 Friday in Indio is already Saturday in UTC; the festival is still tomorrow.
        XCTAssertEqual(f.daysUntil(now: utc("2026-10-10T06:30:00Z")), 1)
        XCTAssertEqual(f.daysUntil(now: utc("2026-10-10T19:00:00Z")), 0)
        XCTAssertLessThan(f.daysUntil(now: utc("2026-10-12T19:00:00Z")), 0)
        XCTAssertEqual(f.daysUntil(now: utc("2026-09-30T19:00:00Z")), 10)
        XCTAssertTrue(f.isUpcomingOrLive(now: utc("2026-10-11T23:00:00Z")))
        XCTAssertFalse(f.isUpcomingOrLive(now: utc("2026-10-12T08:00:00Z")))
        XCTAssertEqual(Countdown.label(daysUntil: 1), "Tomorrow")
        XCTAssertEqual(Countdown.label(daysUntil: 0), "Now on")
        XCTAssertEqual(Countdown.label(daysUntil: 12), "In 12 days")
    }

    func testDateRangeLabel() {
        let clock = FestivalClock(timeZone: la, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(clock.dateRange(festival()), "Oct 10–11")
        XCTAssertEqual(clock.dateRange(festival(start: "2026-10-30", end: "2026-11-01")), "Oct 30 – Nov 1")
        XCTAssertEqual(clock.weekday(LocalDate("2026-10-10")!), "Saturday")
    }
}
