import XCTest

/// Captures Discover, the festival timeline, My Schedule, the wallpaper preview and the Live Activity
/// Lock Screen preview from the `--screenshots` fixture (Saturday 8:05 PM at Head Trip).
/// `scripts/capture-screenshots.sh` sets the appearance and status bar, and passes `SCREENSHOT_DIR`
/// (as `TEST_RUNNER_SCREENSHOT_DIR`). Without it, images are only attached to the result bundle.
final class ScreenshotTests: XCTestCase {
    @MainActor func testScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()

        let festival = app.element("festival-head-trip-2026")
        XCTAssertTrue(festival.waitForExistence(timeout: 20))
        snap("1-discover")

        festival.tap()
        XCTAssertTrue(app.element("festivalTitle").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("set-head-trip-2026-2026-10-10-peggy-gou-b2b-four-tet").exists)
        snap("2-festival")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["My Schedule"].tap()
        XCTAssertTrue(app.element("scheduleDay-2026-10-10").waitForExistence(timeout: 5))
        snap("3-schedule")

        app.tabBars.buttons["Wallpaper"].tap()
        XCTAssertTrue(app.element("wallpaperPreview").waitForExistence(timeout: 5))
        snap("4-wallpaper")

        app.tabBars.buttons["My Schedule"].tap()
        let preview = app.buttons["liveActivityPreviewButton"]
        for _ in 0..<6 where !preview.isHittable { app.swipeUp() }
        preview.tap()
        XCTAssertTrue(app.element("liveActivityLockScreen").waitForExistence(timeout: 5))
        snap("5-live-activity")
    }

    @MainActor private func snap(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertNoThrow(try shot.pngRepresentation.write(to: url.appendingPathComponent("\(name).png")))
    }
}

extension XCUIApplication {
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier].firstMatch
    }
}
