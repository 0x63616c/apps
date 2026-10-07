import XCTest
import UIKit
import ImageIO

final class RedesignUITests: XCTestCase {
    @MainActor override func setUp() {
        super.setUp()
        continueAfterFailure = false
        resetPortraitOrientation()
    }

    @MainActor override func tearDown() {
        resetPortraitOrientation()
        super.tearDown()
    }

    private func screenImage() -> CGImage? {
        // Decode the framebuffer's recorded orientation rather than stretching
        // XCTest's UIImage into a potentially stale application frame.
        guard let source = CGImageSourceCreateWithData(XCUIScreen.main.screenshot().pngRepresentation as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096
        ] as CFDictionary)
    }

    @MainActor private func resetPortraitOrientation() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        waitUntil("Portrait orientation should settle between tests", timeout: 10) {
            guard let image = self.screenImage(), image.height > image.width else { return false }
            return app.state != .runningForeground || app.frame.height > app.frame.width
        }
    }

    @MainActor private func waitUntil(_ message: String, timeout: TimeInterval = 5,
                                     file: StaticString = #filePath, line: UInt = #line,
                                     _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       message, file: file, line: line)
    }

    @MainActor private func assertCentered(_ app: XCUIApplication, id: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let thumbnail = app.buttons["filmstrip-\(id)"]
        let filmstrip = app.scrollViews["galleryFilmstrip"]
        // Test the actual settled frame, not just selection state or existence.
        waitUntil("Selected filmstrip thumbnail \(id) should be centered", file: file, line: line) {
            thumbnail.exists && thumbnail.isSelected && thumbnail.isHittable && filmstrip.exists &&
                thumbnail.frame.width > 0 && abs(thumbnail.frame.midX - filmstrip.frame.midX) <= 3
        }
    }

    @MainActor private func libraryGrid(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews["screenshotGrid"]
    }

    @MainActor private func tapMenuItem(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        var previousFrame: CGRect?
        waitUntil("Menu item \(label) should finish moving before tapping") {
            guard button.exists, button.isEnabled else { return false }
            let frame = button.frame
            defer { previousFrame = frame }
            return frame.width > 0 && frame.height > 0 && frame == previousFrame
        }
        button.tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testNativeSearchAndGallery() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Shots"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["15"].exists)
        let search = app.buttons["Search"]
        XCTAssertTrue(search.exists)
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        capture(app, "library-light")
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        capture(app, "search-expanded")
        // Submit the search before presenting the gallery. Leaving the keyboard
        // focused underneath a full-screen cover can stall simulator idle waits.
        field.typeText("weekend\n")
        XCTAssertTrue(app.staticTexts["4"].waitForExistence(timeout: 3))
        capture(app, "search-results")
        app.buttons["A quieter weekend"].tap()
        XCTAssertTrue(app.buttons["Close screenshot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["filmstrip-sample-0"].exists)
        XCTAssertTrue(app.staticTexts["1 of 4"].exists)
        assertCentered(app, id: "sample-0")
        capture(app, "gallery")
        app.buttons["filmstrip-sample-2"].tap()
        XCTAssertTrue(app.buttons["filmstrip-sample-2"].isSelected)
        XCTAssertTrue(app.staticTexts["2 of 4"].exists)
        assertCentered(app, id: "sample-2")
        let pager = app.collectionViews["galleryPager"]
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["3 of 4"].waitForExistence(timeout: 5))
        assertCentered(app, id: "sample-4")
        capture(app, "gallery-swiped")
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["4 of 4"].waitForExistence(timeout: 5))
        assertCentered(app, id: "sample-12")
        capture(app, "gallery-last-edge")
        pager.swipeRight()
        XCTAssertTrue(app.staticTexts["3 of 4"].waitForExistence(timeout: 5))
        assertCentered(app, id: "sample-4")
        app.buttons["filmstrip-sample-12"].tap()
        XCTAssertTrue(app.staticTexts["4 of 4"].waitForExistence(timeout: 5))
        assertCentered(app, id: "sample-12")
        for position in stride(from: 3, through: 1, by: -1) {
            pager.swipeRight()
            XCTAssertTrue(app.staticTexts["\(position) of 4"].waitForExistence(timeout: 5))
        }
        assertCentered(app, id: "sample-0")
        app.buttons["Close screenshot"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "weekend")
    }

    @MainActor func testAnalysisDetailsShowsDescriptionAndExtractedText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--capture-gallery"]
        app.launch()
        XCTAssertTrue(app.buttons["galleryMore"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["screenshotDescription"].exists)
        app.buttons["galleryMore"].tap()
        tapMenuItem(app, "Analysis details")
        XCTAssertTrue(app.navigationBars["Analysis details"].waitForExistence(timeout: 5))
        let description = app.staticTexts["screenshotDescription"]
        XCTAssertTrue(description.exists)
        XCTAssertTrue(description.label.contains("A quieter weekend"))
        XCTAssertTrue(app.staticTexts["screenshotDescribedAt"].exists)
        XCTAssertTrue(app.staticTexts["screenshotExtractedText"].exists)
        XCTAssertTrue(app.staticTexts["screenshotVisualLabels"].exists)
        capture(app, "analysis-details")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["galleryMore"].waitForExistence(timeout: 5))
        app.buttons["filmstrip-sample-1"].tap()
        app.buttons["galleryMore"].tap()
        tapMenuItem(app, "Analysis details")
        XCTAssertTrue(app.staticTexts["screenshotDescriptionEmpty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["screenshotExtractedText"].exists)
        capture(app, "analysis-details-pending")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Close screenshot"].waitForExistence(timeout: 5))
    }

    @MainActor func testFavoritesFollowScreenshotsAndFilterTheLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--capture-gallery"]
        app.launch()
        let favorite = app.buttons["galleryFavorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        XCTAssertEqual(favorite.label, "Favorite screenshot")
        favorite.tap()
        XCTAssertEqual(favorite.label, "Unfavorite screenshot")
        capture(app, "gallery-favorite")
        app.buttons["filmstrip-sample-1"].tap()
        XCTAssertEqual(favorite.label, "Favorite screenshot")
        favorite.tap()
        app.buttons["filmstrip-sample-0"].tap()
        XCTAssertEqual(favorite.label, "Unfavorite screenshot")
        favorite.tap()
        XCTAssertEqual(favorite.label, "Favorite screenshot")
        app.buttons["Close screenshot"].tap()
        let favorites = app.buttons["Favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        favorites.tap()
        XCTAssertTrue(favorites.isSelected)
        XCTAssertTrue(app.buttons["Objects for every day"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["A quieter weekend"].exists)
        XCTAssertTrue(app.staticTexts["1"].exists)
        capture(app, "favorites-library")
        app.buttons["Objects for every day"].tap()
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertEqual(favorite.label, "Unfavorite screenshot")
        favorite.tap()
        app.buttons["Close screenshot"].tap()
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: 5))
        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["A quieter weekend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["15"].exists)
    }

    @MainActor func testTagIconEditingAndCancel() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        app.buttons["More"].tap()
        app.buttons["Tags"].tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 3))
        capture(app, "tag-list")
        app.collectionViews.buttons["Shopping"].tap()
        XCTAssertTrue(app.textFields["tagName"].waitForExistence(timeout: 3))
        app.buttons["chooseTagIcon"].tap()
        XCTAssertTrue(app.navigationBars["Icons"].waitForExistence(timeout: 3))
        capture(app, "icon-collection")
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Nature")
        app.buttons["Nature"].tap()
        let name = app.textFields["tagName"]
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Picks")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.collectionViews.buttons["Picks"].waitForExistence(timeout: 3))
        app.collectionViews.buttons["Picks"].tap()
        XCTAssertEqual(app.textFields["tagName"].value as? String, "Picks")
        XCTAssertTrue(app.staticTexts["Nature"].exists)
        app.buttons["Cancel"].tap()
        app.buttons["Create tag"].tap()
        app.textFields["tagName"].tap()
        app.textFields["tagName"].typeText("Discard me")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Discard me"].exists)
        app.buttons["Done"].tap()
        app.buttons["Picks"].tap()
        XCTAssertTrue(app.buttons["Objects for every day"].exists)
        XCTAssertTrue(app.staticTexts["1"].exists)
    }
    @MainActor func testGroupingAndReversibleHiding() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["15"].waitForExistence(timeout: 10))
        XCTAssertLessThan(app.staticTexts["Shots"].frame.minX, app.frame.width / 4)
        app.buttons["More"].tap()
        let grouped = app.buttons["Grouped by day"]
        tapMenuItem(app, "Grouped by day")
        let header = app.descendants(matching: .any)["dayHeader"].firstMatch
        // A simulator menu can miss its first synthesized tap while animating.
        // Retry only if that same menu is still open; a dismissed menu with no
        // headers remains a real failure, not a reason to toggle layout again.
        if !header.waitForExistence(timeout: 3), grouped.exists { grouped.tap() }
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        capture(app, "grouped-by-day")
        app.terminate()
        app.launchArguments = ["--preserve-layout"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["dayHeader"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["A quieter weekend"].tap()
        app.buttons["galleryMore"].tap()
        tapMenuItem(app, "Hide")
        XCTAssertTrue(app.staticTexts["1 of 14"].waitForExistence(timeout: 3))
        app.buttons["Close screenshot"].tap()
        XCTAssertFalse(app.buttons["A quieter weekend"].exists)
        XCTAssertTrue(app.staticTexts["14"].exists)
        app.buttons["More"].tap()
        tapMenuItem(app, "Hidden screenshots")
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 3))
        capture(app, "hidden")
        app.buttons["A quieter weekend"].tap()
        app.buttons["galleryMore"].tap()
        tapMenuItem(app, "Unhide")
        XCTAssertTrue(app.staticTexts["No hidden screenshots"].waitForExistence(timeout: 3))
        app.buttons["More"].tap()
        tapMenuItem(app, "Show library")
        XCTAssertTrue(app.buttons["A quieter weekend"].waitForExistence(timeout: 3))
        app.buttons["More"].tap()
        tapMenuItem(app, "Continuous grid")
        XCTAssertFalse(app.descendants(matching: .any)["dayHeader"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["15"].exists)
    }

    @MainActor func testShareAndTagsAreSeparateAccessibleActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--capture-gallery"]
        app.launch()
        let share = app.buttons["galleryShare"]
        let tags = app.buttons["galleryTags"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(tags.exists)
        XCTAssertEqual(share.label, "Share screenshot")
        XCTAssertEqual(tags.label, "Edit tags")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "gallery-actions-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        waitUntil("Share and Tags should be distinct, separated toolbar buttons") {
            share.isEnabled && tags.isEnabled &&
                share.frame.width > 0 && tags.frame.width > 0 &&
                tags.frame.minX - share.frame.maxX >= 44 &&
                abs(share.frame.midY - tags.frame.midY) <= 5
        }
        capture(app, "gallery-separate-actions")
        // Verify the real action instead of relying solely on ShareLink's
        // occasionally false XCTest isHittable result on this simulator.
        share.tap()
        let activityList = app.otherElements["ActivityListView"]
        waitUntil("Share should open the system activity sheet") {
            activityList.exists || app.buttons["Copy"].exists || app.buttons["Save Image"].exists
        }
        capture(app, "gallery-share-sheet")
        if app.buttons["Close"].firstMatch.exists {
            app.buttons["Close"].firstMatch.tap()
        } else if app.otherElements["PopoverDismissRegion"].exists {
            app.otherElements["PopoverDismissRegion"].tap()
        } else {
            activityList.swipeDown()
        }
        XCTAssertTrue(tags.waitForExistence(timeout: 5))
        tags.tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        // Do not invoke external share destinations from the fixture test.
    }

    @MainActor func testGroupedDayHeaderStaysPinnedWhileContentScrolls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--large-library", "--capture-grouped", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["15,000"].waitForExistence(timeout: 20))
        let header = app.descendants(matching: .any)["dayHeader"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let label = header.label
        let grid = libraryGrid(app)
        XCTAssertTrue(grid.exists)
        // Use the header's accessible frame to account for text/padding insets.
        let top = header.frame.minY
        let originalHeaderHeight = header.frame.height
        XCTAssertGreaterThan(originalHeaderHeight, 0)
        // Fixture titles are unique after the first 15 records, so this tracks the original row.
        let row = app.buttons["Saturday plans"].firstMatch
        XCTAssertTrue(row.isHittable)
        let originalRowY = row.frame.minY
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.1, thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        let pinned = app.descendants(matching: .any).matching(identifier: "dayHeader")
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        waitUntil("The same day header should remain at the scroll viewport's top") {
            pinned.exists && pinned.frame.width > 0 &&
                abs(pinned.frame.minY - top) <= 4 &&
                abs(pinned.frame.height - originalHeaderHeight) <= 2
        }
        // Verify content actually moved; an inert scroll must not pass the header check.
        waitUntil("Screenshot rows should move underneath the pinned header") {
            !row.isHittable || row.frame.minY < originalRowY - 30
        }
        capture(app, "grouped-header-pinned")
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.1, thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        waitUntil("Header should remain pinned through another scroll") {
            pinned.exists && abs(pinned.frame.minY - top) <= 4
        }
    }

    @MainActor func testDateHandoffsHaveContinuousOpaqueCoverage() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--capture-grouped", "--header-transitions"] + (dark ? ["--header-dark"] : [])
            app.launch()
            let grid = libraryGrid(app)
            XCTAssertTrue(grid.waitForExistence(timeout: 15))
            let next = app.buttons["nextHeaderSample"]
            let back = app.buttons["previousHeaderSample"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            func metrics() -> [String: Double] {
                Dictionary(uniqueKeysWithValues: (grid.value as? String ?? "").split(separator: ";").compactMap { part in
                    let values = part.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard values.count == 2, let number = Double(values[1]) else { return nil }
                    return (values[0], number)
                })
            }
            func assertOpaqueBand() {
                let values = metrics()
                guard let height = values["headerHeight"], let offset = values["offset"] else {
                    XCTFail("Missing actual layout evidence"); return
                }
                let frame = app.frame
                let gridFrame = grid.frame
                guard let image = screenImage() else { XCTFail("Missing screenshot"); return }
                let width = image.width, pixelHeight = image.height
                XCTAssertEqual(Double(width) / Double(pixelHeight), frame.width / frame.height, accuracy: 0.01,
                               "Framebuffer and accessibility coordinates must have the same orientation")
                var bytes = [UInt8](repeating: 0, count: width * pixelHeight * 4)
                let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress, width: width, height: pixelHeight,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: pixelHeight))
                    return true
                }
                XCTAssertTrue(rendered)
                let scale = Double(width) / frame.width
                let expected = dark ? 0 : 255
                for x in [gridFrame.minX + 8, gridFrame.maxX - 8] {
                    for y in stride(from: gridFrame.minY + 1, to: gridFrame.minY + height - 1, by: 1.0 / scale) {
                        let column = Int(x * scale), row = Int(y * scale)
                        guard (0..<width).contains(column), (0..<pixelHeight).contains(row) else {
                            XCTFail("Header band outside screenshot"); return
                        }
                        let base = (row * width + column) * 4
                        if (0..<3).contains(where: { abs(Int(bytes[base + $0]) - expected) > 3 }) {
                            capture(app, "header-seam-failure-\(dark)-\(offset)")
                            XCTFail("Screenshot pixels leaked into date header band at offset \(offset), x \(x), y \(y)")
                            return
                        }
                    }
                }
            }
            waitUntil("Header fixture should apply the requested appearance") {
                metrics()["style"] == (dark ? 2 : 1)
            }
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                XCUIDevice.shared.orientation = orientation
                var previousFrame: CGRect?
                var previousMetrics: [String: Double]?
                waitUntil("Framebuffer and collection layout should settle after rotation", timeout: 10) {
                    let frame = grid.frame
                    let values = metrics()
                    defer { previousFrame = frame; previousMetrics = values }
                    let application = app.frame
                    guard let image = self.screenImage(), frame == previousFrame, values == previousMetrics,
                          abs(Double(image.width) / Double(image.height) - application.width / application.height) < 0.01 else { return false }
                    return orientation == .portrait ? frame.height > frame.width : frame.width > frame.height
                }
                assertOpaqueBand()
                // Four handoffs, including one-image and partial-row sections.
                for step in 0..<40 {
                    next.tap()
                    assertOpaqueBand()
                    if step == 4 { capture(app, "header-handoff-\(dark)-\(orientation.rawValue)") }
                }
                for _ in 0..<40 { back.tap(); assertOpaqueBand() }
            }
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
    }

    @MainActor func testLargeLibraryOpenPageAndLastEdge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--large-library", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["15,000"].waitForExistence(timeout: 20))
        app.buttons["A quieter weekend"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 of 15,000"].waitForExistence(timeout: 10))
        assertCentered(app, id: "sample-0")
        let pager = app.collectionViews["galleryPager"]
        XCTAssertTrue(pager.exists)
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["2 of 15,000"].waitForExistence(timeout: 5))
        assertCentered(app, id: "sample-1")
        pager.swipeRight()
        XCTAssertTrue(app.staticTexts["1 of 15,000"].waitForExistence(timeout: 5))
        assertCentered(app, id: "sample-0")
        app.buttons["Close screenshot"].tap()
        XCTAssertTrue(app.staticTexts["15,000"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--large-library", "--capture-gallery-last", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["15,000 of 15,000"].waitForExistence(timeout: 20))
        assertCentered(app, id: "sample-14999")
        pager.swipeRight()
        XCTAssertTrue(app.staticTexts["14,999 of 15,000"].waitForExistence(timeout: 5))
        assertCentered(app, id: "sample-14998")
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["15,000 of 15,000"].waitForExistence(timeout: 5))
        assertCentered(app, id: "sample-14999")
        capture(app, "large-library-last-edge")
    }

    @MainActor func testLibraryGridFitsThreeVisibleColumns() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--large-library"]
        app.launch()
        let grid = libraryGrid(app)
        XCTAssertTrue(grid.waitForExistence(timeout: 20))
        let firstRow = ["A quieter weekend", "Objects for every day", "Lemon & olive oil"].map {
            app.buttons[$0].firstMatch
        }
        for button in firstRow {
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable, "First-row screenshot \(button.label) should be visible")
            XCTAssertLessThanOrEqual(button.frame.width, grid.frame.width / 3 + 4)
            XCTAssertGreaterThanOrEqual(button.frame.minX, grid.frame.minX - 1)
            XCTAssertLessThanOrEqual(button.frame.maxX, grid.frame.maxX + 1)
        }
        XCTAssertLessThan(firstRow[0].frame.midX, firstRow[1].frame.midX)
        XCTAssertLessThan(firstRow[1].frame.midX, firstRow[2].frame.midX)
        XCTAssertEqual(firstRow[0].frame.midY, firstRow[2].frame.midY, accuracy: 3)
        capture(app, "library-three-columns")
    }

    @MainActor func testUnchangedPhotoRefreshDoesNotPauseActiveScan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-scan", "--test-refresh-scan"]
        app.launch()
        XCTAssertTrue(app.buttons["Pause scanning"].waitForExistence(timeout: 15))
        let progress = app.progressIndicators["Scan progress"]
        var lastCompleted = 0
        var sawProgress = false
        // Fixture sends real store refreshes every 500ms, with identical metadata.
        // Watch the active phase, not merely the final successful scan result.
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            XCTAssertFalse(app.buttons["Resume scanning"].exists,
                           "Unchanged Photos notifications must not pause an active scan")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "paused")).firstMatch.exists)
            if progress.exists {
                let completed = Int((progress.value as? String ?? "0").split(separator: " ").first ?? "0") ?? 0
                sawProgress = sawProgress || completed > 0
                lastCompleted = max(lastCompleted, completed)
            }
        }
        XCTAssertTrue(sawProgress, "Repeated metadata refreshes must allow indexing to advance")
        XCTAssertGreaterThan(lastCompleted, 0)
        capture(app, "scan-unchanged-photos-refresh")
    }

    @MainActor func testScanProgressCanPauseAndResume() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-scan"]
        app.launch()
        XCTAssertTrue(app.buttons["Pause scanning"].waitForExistence(timeout: 15))
        let progress = app.progressIndicators["Scan progress"]
        let madeProgress = NSPredicate { _, _ in
            let completed = Int((progress.value as? String ?? "0").split(separator: " ").first ?? "0") ?? 0
            return completed > 0
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: madeProgress, object: nil)], timeout: 40), .completed)
        capture(app, "scan-progress")
        app.buttons["Pause scanning"].tap()
        XCTAssertTrue(app.buttons["Resume scanning"].waitForExistence(timeout: 10))
        let pausedValue = progress.value as? String
        let phaseLabel = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Indexing screenshots", "Adding automatic tags")).firstMatch
        func phase() -> String {
            guard phaseLabel.exists else { return "" }
            return phaseLabel.label.hasPrefix("Indexing screenshots") ? "indexing" : "tagging"
        }
        let pausedPhase = phase()
        XCTAssertFalse(pausedPhase.isEmpty)
        capture(app, "scan-paused")
        app.buttons["Resume scanning"].tap()
        XCTAssertTrue(app.buttons["Pause scanning"].waitForExistence(timeout: 3))
        let before = Int((pausedValue ?? "0").split(separator: " ").first ?? "0") ?? 0
        waitUntil("Resuming should preserve completed work within a phase, or advance from indexing to tagging") {
            let resumedPhase = phase()
            let after = Int((progress.value as? String ?? "0").split(separator: " ").first ?? "0") ?? 0
            if resumedPhase == pausedPhase { return after >= before }
            return pausedPhase == "indexing" && resumedPhase == "tagging"
        }
        XCTAssertTrue(app.buttons["Pause scanning"].waitForNonExistence(timeout: 180))
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Last scan"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["lastScanCount"].firstMatch.value as? String, "6")
        capture(app, "scan-timing")
    }

}
