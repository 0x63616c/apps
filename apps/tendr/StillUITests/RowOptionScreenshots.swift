import XCTest

/// APP-6 preview: the Journal → Doses list in each row design option, plus Treatment without L/R,
/// from the synthetic `--demo --screenshots` fixture. Throwaway; not for merge.
final class RowOptionScreenshots: XCTestCase {
    @MainActor func testRowOptions() throws {
        continueAfterFailure = false
        for (index, style) in ["A", "B", "C", "D"].enumerated() {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--screenshots", "-accentColor", "Graphite", "-journalRowStyle", style]
            app.launch()
            XCTAssertTrue(app.buttons["logDose"].waitForExistence(timeout: 15))
            let tabBar = app.tabBars.firstMatch
            if index == 0 {
                tabBar.buttons["Treatment"].tap()
                let history = app.buttons["doseHistoryCard"]
                XCTAssertTrue(history.waitForExistence(timeout: 5))
                for _ in 0..<4 where !history.isHittable { app.swipeUp() }
                snap("treatment-no-side")
            }
            tabBar.buttons["Journal"].tap()
            XCTAssertTrue(app.staticTexts["pageHeader-Journal"].waitForExistence(timeout: 5))
            app.buttons["Doses"].tap()
            Thread.sleep(forTimeInterval: 0.5)
            snap("row-option-\(style)")
            app.terminate()
        }
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
