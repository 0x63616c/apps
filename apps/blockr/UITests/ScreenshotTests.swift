import XCTest
final class ScreenshotTests: XCTestCase {
    @MainActor func testAppStoreScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.staticTexts["pageHeader-Blockr"].waitForExistence(timeout: 15))
        snap("home")
        for page in ["Stats", "Settings"] {
            app.tabBars.buttons[page].tap()
            XCTAssertTrue(app.staticTexts["pageHeader-\(page)"].waitForExistence(timeout: 5))
            snap(page.lowercased())
        }
        app.tabBars.buttons["Lock"].tap()
        snap("groups")
        app.buttons["New group"].tap()
        XCTAssertTrue(app.textFields["group-name"].waitForExistence(timeout: 5))
        snap("group-new")
        app.buttons["Cancel"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.textFields["group-name"].waitForNonExistence(timeout: 5))
        app.buttons["Start a lock"].tap()
        XCTAssertTrue(app.staticTexts["pageHeader-Start a lock"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add custom duration"].waitForExistence(timeout: 5))
        snap("duration")
        app.buttons["Add custom duration"].tap()
        XCTAssertTrue(app.staticTexts["Custom duration"].waitForExistence(timeout: 5))
        snap("custom-duration")
        app.buttons["duration-cancel"].tap()
        XCTAssertTrue(app.buttons["duration-cancel"].waitForNonExistence(timeout: 5))
        app.buttons["Review lock"].tap()
        XCTAssertTrue(app.staticTexts["Ready to lock?"].waitForExistence(timeout: 5))
        snap("confirm")
        app.buttons["Start lock"].tap()
        XCTAssertTrue(app.staticTexts["Let the time pass."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["View group"].exists)
        snap("active")
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings are locked until your lock ends."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Reset this device"].isEnabled)
        snap("settings-locked")
    }
    @MainActor func testSavedDurationLifecycle() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["Start a lock"].waitForExistence(timeout: 15))
        app.buttons["Start a lock"].tap()
        app.buttons["Add custom duration"].tap()
        let hours = app.textFields["Hours"]
        XCTAssertTrue(hours.waitForExistence(timeout: 5))
        hours.tap(); hours.typeText("1")
        let minutes = app.textFields["Minutes"]
        minutes.tap(); minutes.typeText("30")
        if !app.buttons["Save duration"].isHittable { app.swipeUp() }
        app.buttons["Save duration"].tap()
        let custom = app.buttons["1 hour, 30 minutes"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        XCTAssertTrue(custom.isSelected)
        snap("duration-saved")
        app.buttons["Edit saved duration"].tap()
        app.buttons["1h 30m"].tap()
        XCTAssertTrue(app.staticTexts["Edit duration"].waitForExistence(timeout: 5))
        snap("duration-edit")
        if !app.buttons["Delete duration"].isHittable { app.swipeUp() }
        app.buttons["Delete duration"].tap()
        XCTAssertTrue(custom.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["2 hours"].isSelected)
    }
    @MainActor private func snap(_ name: String) {
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
