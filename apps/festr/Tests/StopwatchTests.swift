import XCTest
@testable import FestrCore

final class StopwatchTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)

    func testStartStopResumeExcludesPausedTimeAndRepeatedActionsAreHarmless() {
        var timer = Stopwatch()
        timer.stop(at: epoch)
        timer.start(at: epoch)
        timer.start(at: epoch.addingTimeInterval(5))
        XCTAssertEqual(timer.elapsed(at: epoch.addingTimeInterval(12.5)), 12.5)
        timer.stop(at: epoch.addingTimeInterval(12.5))
        timer.stop(at: epoch.addingTimeInterval(20))
        XCTAssertEqual(timer.elapsed(at: epoch.addingTimeInterval(100)), 12.5)
        timer.start(at: epoch.addingTimeInterval(100))
        XCTAssertEqual(timer.elapsed(at: epoch.addingTimeInterval(103)), 15.5)
        XCTAssertEqual(timer.summary.timerStart, epoch.addingTimeInterval(87.5))
    }

    func testLapsAreSplitsAndExcludePausedTime() {
        var timer = Stopwatch()
        timer.lap(at: epoch)
        XCTAssertTrue(timer.laps.isEmpty)
        timer.start(at: epoch)
        timer.lap(at: epoch.addingTimeInterval(10))
        timer.stop(at: epoch.addingTimeInterval(15))
        timer.lap(at: epoch.addingTimeInterval(20))
        XCTAssertEqual(timer.laps.count, 1)
        timer.start(at: epoch.addingTimeInterval(100))
        timer.lap(at: epoch.addingTimeInterval(107))
        XCTAssertEqual(timer.laps.map(\.duration), [10, 12])
        XCTAssertEqual(timer.laps.map(\.elapsed), [10, 22])
        XCTAssertEqual(timer.summary.lastLap, 12)
        XCTAssertEqual(timer.summary.lapCount, 2)
    }

    func testResetClearsRunningAndPausedTimers() {
        for stopFirst in [false, true] {
            var timer = Stopwatch()
            timer.start(at: epoch)
            timer.lap(at: epoch.addingTimeInterval(5))
            if stopFirst { timer.stop(at: epoch.addingTimeInterval(10)) }
            timer.reset()
            XCTAssertEqual(timer, Stopwatch())
            XCTAssertEqual(timer.elapsed(at: epoch.addingTimeInterval(100)), 0)
        }
    }

    func testCodableRestoresRunningAndPausedTimers() throws {
        var timer = Stopwatch()
        timer.start(at: epoch)
        timer.lap(at: epoch.addingTimeInterval(8))
        var restored = try JSONDecoder().decode(Stopwatch.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(restored, timer)
        XCTAssertEqual(restored.elapsed(at: epoch.addingTimeInterval(3_600)), 3_600)
        restored.stop(at: epoch.addingTimeInterval(3_600))
        let paused = try JSONDecoder().decode(Stopwatch.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(paused.elapsed(at: epoch.addingTimeInterval(7_200)), 3_600)
    }

    func testBackwardsClockDoesNotProduceNegativeTime() {
        var timer = Stopwatch()
        timer.start(at: epoch)
        XCTAssertEqual(timer.elapsed(at: epoch.addingTimeInterval(-10)), 0)
        timer.lap(at: epoch.addingTimeInterval(10))
        timer.lap(at: epoch.addingTimeInterval(5))
        XCTAssertEqual(timer.laps.last?.duration, 0)
    }

    func testActivitySummaryRemainsSmallWithManyLaps() throws {
        var timer = Stopwatch()
        timer.start(at: epoch)
        for second in 1...1_000 { timer.lap(at: epoch.addingTimeInterval(Double(second))) }
        XCTAssertEqual(timer.summary.lapCount, 1_000)
        XCTAssertLessThan(try JSONEncoder().encode(timer.summary).count, 256)
        XCTAssertEqual(StopwatchSummary.formatted(3_661), "01:01:01")
    }

    func testStoreRestoresAndReadsLatestStateBeforeMutating() async throws {
        let epoch = epoch
        try await MainActor.run {
            let suite = "StopwatchTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let first = StopwatchStore(defaults: defaults)
            let second = StopwatchStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
            try first.apply(.start, at: epoch)
            try second.apply(.lap, at: epoch.addingTimeInterval(8))
            let paused = try first.apply(.stop, at: epoch.addingTimeInterval(12))
            XCTAssertEqual(paused.laps.count, 1)
            XCTAssertEqual(second.load().accumulated, 12)
            try second.apply(.reset, at: epoch)
            XCTAssertEqual(first.load(), Stopwatch())
            defaults.set(Data("broken".utf8), forKey: StopwatchStore.storageKey)
            XCTAssertEqual(first.load(), Stopwatch())
        }
    }
}
