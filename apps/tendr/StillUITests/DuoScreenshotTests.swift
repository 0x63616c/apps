import XCTest

/// Uses the same synthetic, in-memory fixture as ScreenshotTests. The host script
/// controls physical displays; rotation here exercises short windows independently.
final class DuoScreenshotTests: XCTestCase {
    private var controlDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["DUO_CONTROL_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    private var canFold: Bool { ProcessInfo.processInfo.environment["DUO_CAN_FOLD"] == "1" }

    @MainActor func testMainScreens() throws {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        for pose in canFold ? ["inner", "outer"] : ["default"] {
            if canFold { try request("pose", name: pose) }
            XCUIDevice.shared.orientation = .portrait
            let app = launchFixture()
            if canFold { assertNavigation(for: pose, in: app) }
            try snap("home")

            select("Treatment", in: app)
            XCTAssertTrue(app.buttons["editSchedule"].waitForExistence(timeout: 5))
            try snap("treatment")
            select("Progress", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["currentWeightCard"].waitForExistence(timeout: 5))
            try snap("progress")
            select("Journal", in: app)
            XCTAssertTrue(app.buttons["Doses"].waitForExistence(timeout: 5))
            app.buttons["Doses"].tap()
            XCTAssertTrue(app.staticTexts["7.5 mg · Weekly medication"].firstMatch.waitForExistence(timeout: 5))
            try snap("journal")
            select("Settings", in: app)
            XCTAssertTrue(app.staticTexts["pageHeader-Settings"].waitForExistence(timeout: 5))
            try snap("settings")

            select("Home", in: app)
            app.buttons["logDose"].tap()
            let amount = app.textFields["doseAmount"]
            XCTAssertTrue(amount.waitForExistence(timeout: 5))
            amount.tap()
            amount.typeText("7.5")
            try snap("log-dose")
            XCUIDevice.shared.orientation = .landscapeLeft
            waitUntil("The app must actually rotate into landscape") {
                let frame = app.windows.firstMatch.frame
                return frame.width > frame.height
            }
            XCTAssertEqual(amount.value as? String, "7.5", "Rotation must preserve an unsaved dose")
            XCTAssertTrue(app.buttons["saveDose"].isHittable, "Save stays above the keyboard")
            try snap("landscape-log-dose")
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["logDose"].waitForExistence(timeout: 5))
            try snap("landscape-home")
            select("Progress", in: app)
            try snap("landscape-progress")
            app.terminate()
        }
    }

    @MainActor func testLiveFoldPreservesNavigationAndDraft() throws {
        continueAfterFailure = false
        try XCTSkipUnless(canFold, "simctl does not expose a supported live-fold control; see capture-notes.txt")
        defer { XCUIDevice.shared.orientation = .portrait }
        try request("pose", name: "inner")
        XCUIDevice.shared.orientation = .portrait
        let app = launchFixture()
        assertNavigation(for: "inner", in: app)
        // Section navigation must remain recoverable after hiding the sidebar.
        let toggle = app.buttons["toggleSidebar"]
        toggle.tap()
        waitUntil("Sidebar can be hidden") { toggle.label == "Show sidebar" }
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        assertNavigation(for: "inner", in: app)
        select("Journal", in: app)
        app.buttons["Doses"].tap()
        select("Home", in: app)
        let card = app.descendants(matching: .any)["medicationCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let detail = app.descendants(matching: .any)["medicationDetailChart"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        detail.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: detail.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)))
        XCTAssertTrue(app.buttons["Live"].waitForExistence(timeout: 3), "Scrubbing selects a past time")
        try request("pose", name: "outer")
        assertNavigation(for: "outer", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "Folding keeps the pushed destination")
        XCTAssertTrue(app.buttons["Live"].exists, "Folding keeps the chart selection")
        select("Progress", in: app)
        select("Home", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "Each section keeps its own stack")
        waitUntil("Returning to Home explicitly restores the live chart") { !app.buttons["Live"].exists }
        try request("pose", name: "inner")
        assertNavigation(for: "inner", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        select("Journal", in: app)
        XCTAssertTrue(app.buttons["Doses"].isSelected, "Journal filter survives folding and section changes")
        select("Home", in: app)
        let back = app.navigationBars["Medication"].buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["logDose"].waitForExistence(timeout: 5))
        app.buttons["logDose"].tap()
        let amount = app.textFields["doseAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("7.5")
        for pose in ["outer", "inner", "outer"] {
            let previousSize = app.windows.firstMatch.frame.size
            try request("pose", name: pose)
            waitUntil("A fold must resize the app window while the sheet is open") {
                app.windows.firstMatch.frame.size != previousSize
            }
            XCTAssertTrue(amount.waitForExistence(timeout: 5), "The sheet stays presented")
            XCTAssertEqual(amount.value as? String, "7.5", "Folding keeps the unsaved draft")
            XCTAssertTrue(app.buttons["saveDose"].isHittable)
        }
        app.buttons["Cancel"].tap()
        assertNavigation(for: "outer", in: app)
    }

    @MainActor private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--screenshots", "-accentColor", "Graphite"]
        app.launch()
        XCTAssertTrue(app.buttons["logDose"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func select(_ section: String, in app: XCUIApplication) {
        let identified = app.buttons.matching(identifier: "nav\(section)")
        if let button = identified.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            button.tap()
        } else {
            let tab = app.tabBars.buttons[section]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Section must be reachable in either layout")
            tab.tap()
        }
    }

    @MainActor private func assertNavigation(for pose: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons["Home"]
        let sidebarHome = app.descendants(matching: .any)["sectionSidebar"].buttons["navHome"]
        if pose == "inner" {
            waitUntil("Inner display must expose the regular-width sidebar") { sidebarHome.isHittable }
            XCTAssertFalse(tab.isHittable, "Regular width must hide the compact tab bar")
        } else {
            waitUntil("Outer display must expose the compact tab bar") { tab.isHittable }
            XCTAssertFalse(sidebarHome.isHittable, "Compact width must stay in the detail column")
        }
    }

    @MainActor private func waitUntil(_ message: String, timeout: TimeInterval = 10, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertTrue(condition(), message)
    }

    @MainActor private func snap(_ name: String) throws {
        Thread.sleep(forTimeInterval: 1.5)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if controlDirectory != nil {
            // The test waits while the host captures the active or named displays.
            try request("capture", name: name)
        } else if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: url.appendingPathComponent("default-\(name).png"))
        }
    }

    @MainActor private func request(_ action: String, name: String) throws {
        let directory = try XCTUnwrap(controlDirectory)
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "action": action, "name": name])
        try data.write(to: directory.appendingPathComponent("request.json"), options: .atomic)
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if let responseData = try? Data(contentsOf: directory.appendingPathComponent("response.json")),
               let response = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any],
               response["id"] as? String == id {
                guard response["ok"] as? Bool == true else {
                    XCTFail(response["error"] as? String ?? "Duo capture failed")
                    throw NSError(domain: "DuoCapture", code: 1)
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Timed out waiting for the Duo simulator capture helper")
        throw NSError(domain: "DuoCapture", code: 2)
    }
}
