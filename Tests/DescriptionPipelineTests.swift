import Foundation
import XCTest
@testable import ShotsCore

final class DescriptionPipelineTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testVersionOneIndexWithoutDescriptionFieldsStillDecodes() throws {
        let tag = IndexSnapshot.defaultTags[0]
        let record = Screenshot(id: "legacy", createdAt: date, text: "Order placed",
                                aiTagIDs: [tag.id], removedTagIDs: [tag.id], scannedAt: date)
        let snapshot = IndexSnapshot(tags: [tag], screenshots: [record])
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        legacy.removeValue(forKey: "categoryDiscoveryCount")
        legacy.removeValue(forKey: "categoryDiscoveryCompleted")
        legacy.removeValue(forKey: "dismissedCategoryNames")
        var records = legacy["screenshots"] as! [[String: Any]]
        for key in ["contentDescription", "describedAt", "descriptionUsesImage", "favoritedAt"] {
            records[0].removeValue(forKey: key)
        }
        legacy["screenshots"] = records
        let decoded = try JSONDecoder().decode(IndexSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.tags, [tag])
        XCTAssertEqual(decoded.screenshots, [record])
        XCTAssertNil(decoded.categoryDiscoveryCount)
        XCTAssertNil(decoded.categoryDiscoveryCompleted)
        XCTAssertNil(decoded.dismissedCategoryNames)
        XCTAssertNil(decoded.screenshots[0].contentDescription)
        XCTAssertNil(decoded.screenshots[0].describedAt)
        XCTAssertNil(decoded.screenshots[0].descriptionUsesImage)
        XCTAssertNil(decoded.screenshots[0].favoritedAt)
    }

    func testDescriptionAndDiscoveryMetadataRoundTripPreservesManualIntent() throws {
        let added = Tag(name: "Tickets"), removed = Tag(name: "Shopping")
        let record = Screenshot(id: "ticket", createdAt: date, text: "Saturday",
                                contentDescription: "A festival ticket for Saturday, with a QR code.",
                                describedAt: date, descriptionUsesImage: true,
                                aiTagIDs: [removed.id], addedTagIDs: [added.id], removedTagIDs: [removed.id],
                                scannedAt: date, taggedRevision: 4, favoritedAt: date)
        let snapshot = IndexSnapshot(tagRevision: 4, tags: [added, removed], screenshots: [record],
                                     categoryDiscoveryCount: 32, categoryDiscoveryCompleted: true,
                                     dismissedCategoryNames: ["Promotions"])
        let decoded = try JSONDecoder().decode(IndexSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.screenshots, [record])
        XCTAssertEqual(decoded.categoryDiscoveryCount, 32)
        XCTAssertEqual(decoded.categoryDiscoveryCompleted, true)
        XCTAssertEqual(decoded.screenshots[0].favoritedAt, date)
        XCTAssertEqual(decoded.dismissedCategoryNames, ["Promotions"])
        XCTAssertEqual(TagRules.effectiveTags(for: decoded.screenshots[0], allowed: [added.id, removed.id]), [added.id])
    }

    func testDescriptionsSupplySearchableVisualContextAlongsideOCRAndTags() {
        let tag = Tag(name: "Orders")
        let record = Screenshot(id: "order", createdAt: date, text: "Arriving Friday",
                                contentDescription: "Amazon confirmation for café headphones.",
                                describedAt: date, aiTagIDs: [tag.id])
        let prepared = SearchEngine.prepare(record, tags: [tag])
        XCTAssertTrue(prepared.matches(query: "HEADPHONES friday orders cafe", filter: .tag(tag.id)))
        XCTAssertFalse(prepared.matches(query: "headphones tickets", filter: .all))
        XCTAssertFalse(prepared.matches(query: "headphones", filter: .untagged))
        var oldRecord = record
        oldRecord.contentDescription = nil
        XCTAssertFalse(SearchEngine.matches(oldRecord, tags: [tag], query: "headphones", filter: .all))
        XCTAssertTrue(SearchEngine.matches(oldRecord, tags: [tag], query: "Friday", filter: .all))
    }

    func testDiscoveryUsesSuccessfulVisibleDescriptionsAndDeduplicatesBeforeSampling() {
        let records = [
            Screenshot(id: "hidden", createdAt: date.addingTimeInterval(5), contentDescription: "Private chat",
                       describedAt: date, hiddenAt: date),
            Screenshot(id: "failed", createdAt: date.addingTimeInterval(4), contentDescription: "Unfinished description",
                       lastError: "Unavailable"),
            Screenshot(id: "empty", createdAt: date.addingTimeInterval(3), contentDescription: " \n ", describedAt: date),
            Screenshot(id: "new", createdAt: date.addingTimeInterval(2), contentDescription: "An order", describedAt: date),
            Screenshot(id: "duplicate", createdAt: date.addingTimeInterval(1), contentDescription: "An order", describedAt: date),
            Screenshot(id: "old", createdAt: date, contentDescription: "A rave timetable", describedAt: date)
        ]
        XCTAssertEqual(TagRules.discoverySample(records: records, limit: 2), ["[2 screenshots] An order", "A rave timetable"])
        XCTAssertEqual(TagRules.discoverySample(records: records, limit: 0), [])
        XCTAssertEqual(TagRules.discoverySample(records: records, limit: -1), [])
    }

    func testDiscoverySampleSpansLibraryRatherThanOnlyRecentScreenshots() {
        let records = (0..<100).map {
            Screenshot(id: "photo-\($0)", createdAt: date.addingTimeInterval(Double($0)),
                       contentDescription: "Content \($0)", describedAt: date)
        }
        let sample = TagRules.discoverySample(records: records, limit: 5)
        XCTAssertEqual(sample.count, 5)
        XCTAssertEqual(sample.first, "Content 99")
        XCTAssertEqual(sample.last, "Content 0")
        XCTAssertEqual(Set(sample).count, 5)
        XCTAssertEqual(sample, TagRules.discoverySample(records: records.reversed(), limit: 5))
        XCTAssertEqual(TagRules.discoverySample(records: records).count, 32)
    }

    func testDiscoveryBoundsIndividualDescriptionLengthAndOrdersTiesDeterministically() {
        let records = [
            Screenshot(id: "b", createdAt: date, contentDescription: "Second", describedAt: date),
            Screenshot(id: "a", createdAt: date, contentDescription: String(repeating: "👩🏽‍💻", count: 300), describedAt: date)
        ]
        let sample = TagRules.discoverySample(records: records)
        XCTAssertEqual(sample.count, 2)
        XCTAssertTrue(sample.allSatisfy { $0.count <= 240 })
        XCTAssertEqual(sample.last, "Second")
        XCTAssertEqual(sample, TagRules.discoverySample(records: records.reversed()))
    }

    func testDiscoveredCategoriesRejectInvalidDuplicateAndDismissedNames() {
        let tags = [Tag(name: "Café"), Tag(name: "Tickets")]
        let added = TagRules.categoriesToAdd(
            names: ["CAFE", " \n ", String(repeating: "x", count: 33), "tIcKeTs", "promotions", "  Rave\n times  ", "RAVE TIMES", "Orders"],
            existing: tags, dismissed: ["Prómotions"])
        XCTAssertEqual(added.map(\.name), ["Rave times", "Orders"])
        XCTAssertEqual(Set(added.map(\.id)).count, 2)
        XCTAssertTrue(added.allSatisfy { TagIcon.all.contains($0.icon) })
    }

    func testDiscoveryAdditionCapsRespectExistingTaxonomySize() {
        let names = (0..<40).map { "Category \($0)" }
        XCTAssertEqual(TagRules.categoriesToAdd(names: names, existing: [], dismissed: []).count, 8)
        let existing = (0..<30).map { Tag(name: "Existing \($0)") }
        XCTAssertEqual(TagRules.categoriesToAdd(names: names, existing: existing, dismissed: []).count, 2)
        XCTAssertEqual(TagRules.categoriesToAdd(names: names, existing: existing + [Tag(name: "One"), Tag(name: "Two")], dismissed: []), [])
        XCTAssertTrue(IndexSnapshot().tags.isEmpty)
    }

    func testDiscoveryRetriesEmptyAttemptsAsLibraryGrowsWithoutRepeatingSameSample() {
        XCTAssertFalse(TagRules.discoveryIsDue(count: 1, lastCount: nil, completed: false))
        XCTAssertTrue(TagRules.discoveryIsDue(count: 2, lastCount: nil, completed: false))
        XCTAssertFalse(TagRules.discoveryIsDue(count: 2, lastCount: 2, completed: false))
        XCTAssertFalse(TagRules.discoveryIsDue(count: 3, lastCount: 2, completed: false))
        XCTAssertTrue(TagRules.discoveryIsDue(count: 4, lastCount: 2, completed: false))
        XCTAssertFalse(TagRules.discoveryIsDue(count: 7, lastCount: 4, completed: false))
        XCTAssertTrue(TagRules.discoveryIsDue(count: 8, lastCount: 4, completed: false))
        XCTAssertFalse(TagRules.discoveryIsDue(count: 249, lastCount: 150, completed: false))
        XCTAssertTrue(TagRules.discoveryIsDue(count: 250, lastCount: 150, completed: false))
    }

    func testEstablishedDiscoveryNeedsHundredNewDescriptionsUnlessInvalidated() {
        XCTAssertFalse(TagRules.discoveryIsDue(count: 131, lastCount: 32, completed: true))
        XCTAssertTrue(TagRules.discoveryIsDue(count: 132, lastCount: 32, completed: true))
        XCTAssertFalse(TagRules.discoveryIsDue(count: 10, lastCount: 32, completed: true))
        // A rescan or vision upgrade invalidates the watermark while preserving categories.
        XCTAssertTrue(TagRules.discoveryIsDue(count: 32, lastCount: nil, completed: true))
        XCTAssertFalse(TagRules.discoveryIsDue(count: 0, lastCount: nil, completed: true))
    }

    func testFavoriteFilterAndSearchApplyAlongsideScreenshotText() {
        let tag = Tag(name: "Tickets")
        var record = Screenshot(id: "favorite", createdAt: date, text: "Saturday admission",
                                contentDescription: "A festival ticket", aiTagIDs: [tag.id], favoritedAt: date)
        let favorite = SearchEngine.prepare(record, tags: [tag])
        XCTAssertTrue(favorite.isFavorite)
        XCTAssertTrue(favorite.matches(query: "ticket saturday", filter: .favorites))
        XCTAssertTrue(favorite.matches(query: "FAVORITES", filter: .all))
        XCTAssertTrue(favorite.matches(query: "favorites", filter: .tag(tag.id)))
        XCTAssertFalse(favorite.matches(query: "Sunday", filter: .favorites))
        XCTAssertFalse(favorite.matches(query: "", filter: .untagged))
        record.favoritedAt = nil
        let normal = SearchEngine.prepare(record, tags: [tag])
        XCTAssertFalse(normal.isFavorite)
        XCTAssertFalse(normal.matches(query: "", filter: .favorites))
        XCTAssertFalse(normal.matches(query: "favorites", filter: .all))
        XCTAssertTrue(normal.matches(query: "Saturday", filter: .all))
    }

    func testFavoriteSurvivesAIReassignmentAndCategoryPruning() throws {
        let old = Tag(name: "Shopping"), new = Tag(name: "Tickets")
        var record = Screenshot(id: "saved", createdAt: date, aiTagIDs: [old.id], favoritedAt: date)
        TagRules.set(tagID: old.id, assigned: false, on: &record)
        TagRules.set(tagID: new.id, assigned: true, on: &record)
        record.aiTagIDs = [new.id]
        TagRules.prune(&record, allowed: [new.id])
        XCTAssertEqual(record.favoritedAt, date)
        XCTAssertEqual(TagRules.effectiveTags(for: record, allowed: [new.id]), [new.id])
        let decoded = try JSONDecoder().decode(Screenshot.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
        XCTAssertTrue(SearchEngine.matches(decoded, tags: [new], query: "", filter: .favorites))
    }

    func testDefaultMigrationPreservesManualAssignmentsRemovalsAndEditedTags() {
        var tags = IndexSnapshot.defaultTags
        let addedID = tags[0].id, removedID = tags[1].id
        tags[2].name = "Trips"
        tags[3].iconName = "heart"
        let custom = Tag(name: "Shopping")
        tags.append(custom)
        let records = [Screenshot(id: "one", createdAt: date, aiTagIDs: Set(tags.map(\.id)),
                                  addedTagIDs: [addedID], removedTagIDs: [removedID], hiddenAt: date)]
        let retired = TagRules.retireableDefaultIDs(tags: tags, records: records)
        XCTAssertEqual(retired, Set(IndexSnapshot.defaultTags.dropFirst(4).map(\.id)))
        XCTAssertFalse(retired.contains(custom.id))
        XCTAssertEqual(TagRules.retireableDefaultIDs(tags: IndexSnapshot.defaultTags, records: []),
                       Set(IndexSnapshot.defaultTags.map(\.id)))
    }
}
