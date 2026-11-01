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
        app.buttons["Start a lock"].tap()
        app.buttons["Add custom duration"].tap()
        XCTAssertTrue(app.staticTexts["Custom duration"].waitForExistence(timeout: 5))
        snap("custom-duration")
        app.buttons["duration-cancel"].tap()
        app.buttons["Review lock"].tap()
        XCTAssertTrue(app.staticTexts["Ready to lock?"].waitForExistence(timeout: 5))
        snap("confirm")
        app.buttons["Start lock"].tap()
        XCTAssertTrue(app.staticTexts["Let the time pass."].waitForExistence(timeout: 5))
        snap("active")
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
