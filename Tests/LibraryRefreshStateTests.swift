import Foundation
import XCTest
@testable import ShotsCore

final class LibraryRefreshStateTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 100)

    func testIdenticalSnapshotsAndEmptyLibraryAreNoOp() {
        let items = [PhotoItem(id: "one", createdAt: date, modifiedAt: date)]
        XCTAssertFalse(ScreenshotSnapshotChange.isRelevant(previous: items, fetched: items))
        XCTAssertFalse(ScreenshotSnapshotChange.isRelevant(previous: [], fetched: []))
        XCTAssertTrue(ScreenshotSnapshotChange.isRelevant(previous: nil, fetched: []))
    }

    func testUnrelatedPhotoMetadataDoesNotChangeScreenshotSnapshot() {
        // These stand in for Photos callbacks (favorite/resource-delivery state).
        // The production change tracker projects only these three index fields.
        struct Asset {
            var id: String
            var favorite: Bool
            var downloaded: Bool
            var modifiedAt: Date?
        }
        func snapshot(_ asset: Asset) -> [PhotoItem] {
            [PhotoItem(id: asset.id, createdAt: date, modifiedAt: asset.modifiedAt)]
        }
        let before = Asset(id: "one", favorite: false, downloaded: false, modifiedAt: date)
        var after = before
        after.favorite = true
        after.downloaded = true
        XCTAssertFalse(ScreenshotSnapshotChange.isRelevant(previous: snapshot(before), fetched: snapshot(after)))
        after.modifiedAt = date.addingTimeInterval(1)
        XCTAssertTrue(ScreenshotSnapshotChange.isRelevant(previous: snapshot(before), fetched: snapshot(after)))
    }

    func testAdditionRemovalModificationAndCreationDateAreRelevant() {
        let item = PhotoItem(id: "one", createdAt: date)
        XCTAssertTrue(ScreenshotSnapshotChange.isRelevant(previous: [], fetched: [item]))
        XCTAssertTrue(ScreenshotSnapshotChange.isRelevant(previous: [item], fetched: []))
        XCTAssertTrue(ScreenshotSnapshotChange.isRelevant(previous: [item], fetched: [
            PhotoItem(id: "two", createdAt: date)
        ]))
        XCTAssertTrue(ScreenshotSnapshotChange.isRelevant(previous: [item], fetched: [
            PhotoItem(id: "one", createdAt: date, modifiedAt: date)
        ]))
        XCTAssertTrue(ScreenshotSnapshotChange.isRelevant(previous: [item], fetched: [
            PhotoItem(id: "one", createdAt: date.addingTimeInterval(1))
        ]))
    }

    func testFetchAndCheckpointSnapshotsRejectedAfterNewerChangeOrCancellation() {
        var generation = LibraryRefreshGeneration()
        let fetching = generation.invalidate()
        XCTAssertTrue(generation.accepts(fetching, cancelled: false))
        let newer = generation.invalidate()
        XCTAssertFalse(generation.accepts(fetching, cancelled: false))
        XCTAssertTrue(generation.accepts(newer, cancelled: false))
        XCTAssertFalse(generation.accepts(newer, cancelled: true))
        let checkpointing = generation.current
        generation.invalidate() // Scene or permission changed while stopScan awaited.
        XCTAssertFalse(generation.accepts(checkpointing, cancelled: false))
        XCTAssertTrue(generation.accepts(generation.current, cancelled: false))
    }

    func testLargeIdenticalSnapshotRemainsNoOpDuringRepeatedImageDelivery() {
        let items = (0..<15_000).map { PhotoItem(id: "item-\($0)", createdAt: date) }
        for _ in 0..<10 {
            XCTAssertFalse(ScreenshotSnapshotChange.isRelevant(previous: items, fetched: items))
        }
        var changed = items
        changed[14_999].modifiedAt = date
        XCTAssertTrue(ScreenshotSnapshotChange.isRelevant(previous: items, fetched: changed))
    }
}
