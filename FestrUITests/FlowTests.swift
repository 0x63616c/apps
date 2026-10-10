import XCTest

final class FlowTests: XCTestCase {
    let peggy = "set-head-trip-2026-2026-10-10-peggy-gou-b2b-four-tet"
    let sunflower = "set-head-trip-2026-2026-10-10-floating-points-sunflower-sound-system"

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Friday before Head Trip, 6 PM in Indio.
        app.launchArguments = ["--reset", "--now", "2026-10-10T01:00:00Z"]
        app.launch()
        return app
    }

    @MainActor func testFavouriteFilter() {
        let app = launch()
        XCTAssertTrue(app.element("festival-head-trip-2026").waitForExistence(timeout: 20))
        app.segmentedControls.buttons["Favourites"].tap()
        XCTAssertFalse(app.element("festival-head-trip-2026").waitForExistence(timeout: 1))
        app.segmentedControls.buttons["All"].tap()
        let heart = app.buttons["favourite-head-trip-2026"]
        XCTAssertTrue(heart.waitForExistence(timeout: 3))
        heart.tap()
        XCTAssertEqual(heart.label, "Remove from favourites")
        app.segmentedControls.buttons["Favourites"].tap()
        XCTAssertTrue(app.element("festival-head-trip-2026").waitForExistence(timeout: 3))
    }

    @MainActor func testPickingSetsBuildsTheScheduleAndFlagsClashes() {
        let app = launch()
        app.element("festival-head-trip-2026").tap()
        let peggySet = app.element(peggy)
        XCTAssertTrue(peggySet.waitForExistence(timeout: 5))
        XCTAssertEqual(peggySet.value as? String, "Not in My Schedule")
        peggySet.tap()
        XCTAssertEqual(app.element(peggy).value as? String, "In My Schedule")

        app.element(sunflower).tap()
        XCTAssertEqual(app.element(sunflower).value as? String, "In My Schedule, clashing")
        XCTAssertEqual(app.element(peggy).value as? String, "In My Schedule, clashing")

        app.tabBars.buttons["My Schedule"].tap()
        XCTAssertTrue(app.element("scheduleDay-2026-10-10").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Peggy Gou b2b Four Tet"].exists)
        XCTAssertTrue(app.staticTexts["2 clashing"].exists)

        app.tabBars.buttons["Discover"].tap()
        app.element(sunflower).tap()
        XCTAssertEqual(app.element(peggy).value as? String, "In My Schedule")
    }

    @MainActor func testWallpaperOptions() {
        let app = launch()
        app.tabBars.buttons["Wallpaper"].tap()
        XCTAssertTrue(app.element("wallpaperPreview").waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Full lineup"].tap()
        app.element("theme-paper").tap()
        XCTAssertTrue(app.element("saveAllWallpapers").exists)
        XCTAssertTrue(app.element("wallpaperPreview").exists)
    }
}
