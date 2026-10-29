import XCTest

/// PR preview screens from the synthetic `--demo --screenshots` fixture (twelve weekly doses
/// alternating L/R sides, no real health data). `scripts/capture-screenshots.sh` with
/// `SCREENSHOT_TEST_KEY=pr_screenshot_test` collects the PNGs written to `SCREENSHOT_DIR`;
/// `.github/workflows/pr-screenshots.yml` posts them on UI pull requests.
final class PRScreenshotTests: XCTestCase {
    @MainActor func testPRPreviewScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--screenshots", "-accentColor", "Graphite"]
        app.launch()
        XCTAssertTrue(app.buttons["logDose"].waitForExistence(timeout: 15))

        // Every tab must show its title on first launch, before any tab is touched (APP-3).
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        for title in ["Home", "Treatment", "Progress", "Journal", "Settings"] {
            XCTAssertTrue(tabBar.buttons[title].exists, "\(title) tab is missing")
        }
        snap("tab-bar")

        tabBar.buttons["Treatment"].tap()
        let history = app.buttons["doseHistoryCard"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        for _ in 0..<4 where !history.isHittable { app.swipeUp() }
        snap("treatment")

        tabBar.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["pageHeader-Journal"].waitForExistence(timeout: 5))
        app.buttons["Doses"].tap()
        XCTAssertTrue(app.staticTexts["7.5 mg · Weekly medication"].firstMatch.waitForExistence(timeout: 5))
        snap("journal")
    }

    @MainActor private func snap(_ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
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
