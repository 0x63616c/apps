import Foundation
import XCTest
@testable import ShotsCore

final class TagRulesTests: XCTestCase {
    func testCompactSuggestionsRejectInvalidIndicesAndDeduplicate() {
        let tags = [Tag(name: "Travel"), Tag(name: "Food"), Tag(name: "Work")]
        XCTAssertEqual(TagRules.suggestedIDs(indices: [2, 0, 2, 1], tags: tags), Set(tags.map(\.id)))
        XCTAssertEqual(TagRules.suggestedIDs(indices: [-1, Int.min, Int.max, 3], tags: tags), [])
        XCTAssertEqual(TagRules.suggestedIDs(indices: [0], tags: []), [])
    }

    func testCompactSuggestionsAreBoundedToTheRequestTaxonomy() {
        let tags = (0..<32).map { Tag(name: "Tag \($0)") }
        XCTAssertEqual(TagRules.suggestedIDs(indices: Array(0..<32), tags: tags), Set(tags.prefix(4).map(\.id)))
        XCTAssertEqual(TagRules.suggestedIDs(indices: [31], tags: tags), [tags[31].id])
        let reordered = [tags[31], tags[0]]
        XCTAssertEqual(TagRules.suggestedIDs(indices: [0], tags: reordered), [tags[31].id])
    }

    func testCompactModelSuggestionsNeverUndoManualIntent() {
        let tags = [Tag(name: "Travel"), Tag(name: "Food"), Tag(name: "Work")]
        var record = Screenshot(id: "asset", createdAt: .distantPast)
        TagRules.set(tagID: tags[0].id, assigned: true, on: &record)
        TagRules.set(tagID: tags[1].id, assigned: false, on: &record)
        record.aiTagIDs = TagRules.suggestedIDs(indices: [1, 2], tags: tags)
        XCTAssertEqual(TagRules.effectiveTags(for: record, allowed: Set(tags.map(\.id))), [tags[0].id, tags[2].id])
        record.aiTagIDs = TagRules.suggestedIDs(indices: [], tags: tags)
        XCTAssertEqual(TagRules.effectiveTags(for: record, allowed: Set(tags.map(\.id))), [tags[0].id])
        XCTAssertEqual(record.addedTagIDs, [tags[0].id])
        XCTAssertEqual(record.removedTagIDs, [tags[1].id])
    }

    func testManualChoicesSurviveRescans() {
        let keep = UUID(), remove = UUID(), inferred = UUID()
        let allowed: Set<UUID> = [keep, remove, inferred]
        var record = Screenshot(id: "photo", createdAt: .distantPast, aiTagIDs: [keep, remove])
        TagRules.set(tagID: keep, assigned: true, on: &record)
        TagRules.set(tagID: remove, assigned: false, on: &record)
        record.aiTagIDs = [remove, inferred]
        XCTAssertEqual(TagRules.effectiveTags(for: record, allowed: allowed), [keep, inferred])

        TagRules.set(tagID: remove, assigned: true, on: &record)
        XCTAssertTrue(TagRules.effectiveTags(for: record, allowed: allowed).contains(remove))
        XCTAssertFalse(record.removedTagIDs.contains(remove))
        TagRules.set(tagID: keep, assigned: false, on: &record)
        record.aiTagIDs.insert(keep)
        XCTAssertFalse(TagRules.effectiveTags(for: record, allowed: allowed).contains(keep))
        XCTAssertFalse(record.addedTagIDs.contains(keep))
    }

    func testDeletionIgnoresAndPrunesDanglingIDs() {
        let retained = UUID(), deleted = UUID()
        var record = Screenshot(id: "photo", createdAt: .distantPast,
                                aiTagIDs: [retained, deleted], addedTagIDs: [deleted],
                                removedTagIDs: [deleted])
        XCTAssertEqual(TagRules.effectiveTags(for: record, allowed: [retained]), [retained])
        TagRules.prune(&record, allowed: [retained])
        XCTAssertEqual(record.aiTagIDs, [retained])
        XCTAssertTrue(record.addedTagIDs.isEmpty)
        XCTAssertTrue(record.removedTagIDs.isEmpty)
    }

    func testValidatedNameNormalizesWhitespaceAndRejectsEquivalentNames() throws {
        let tag = Tag(name: "Café Trips")
        XCTAssertEqual(try TagRules.validatedName(" \n New\tTag  ", tags: [tag]), "New Tag")
        XCTAssertThrowsError(try TagRules.validatedName(" CAFE\tTrips ", tags: [tag])) {
            XCTAssertEqual($0 as? TagNameError, .duplicate)
        }
        XCTAssertEqual(try TagRules.validatedName("CAFE Trips", tags: [tag], excluding: tag.id), "CAFE Trips")
        XCTAssertThrowsError(try TagRules.validatedName("\n \t", tags: [])) {
            XCTAssertEqual($0 as? TagNameError, .empty)
        }
        XCTAssertThrowsError(try TagRules.validatedName(String(repeating: "a", count: 33), tags: [])) {
            XCTAssertEqual($0 as? TagNameError, .tooLong)
        }
        let composed = String(repeating: "👩🏽‍💻", count: 32)
        XCTAssertEqual(try TagRules.validatedName(composed, tags: []), composed)
    }

    func testDefaultTaxonomyIsStableAndUnique() {
        let first = IndexSnapshot(), second = IndexSnapshot()
        XCTAssertEqual(first.tags, second.tags)
        XCTAssertEqual(Set(first.tags.map(\.id)).count, first.tags.count)
        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(first.tagRevision, 1)
    }

    func testSerializationPreservesManualOverridesAndScanState() throws {
        let tag = Tag(name: "Travel")
        let record = Screenshot(id: "asset-id", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                                modifiedAt: Date(timeIntervalSince1970: 1_700_000_001), title: "Café map",
                                text: "東京", visualLabels: ["Map"], aiTagIDs: [tag.id],
                                addedTagIDs: [UUID()], removedTagIDs: [tag.id],
                                scannedAt: Date(timeIntervalSince1970: 1_700_000_002),
                                taggedRevision: 3, lastError: "Model unavailable")
        let snapshot = IndexSnapshot(tagRevision: 4, tags: [tag], screenshots: [record])
        let decoded = try JSONDecoder().decode(IndexSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.screenshots, [record])
        XCTAssertEqual(decoded.tags, [tag])
        XCTAssertEqual(decoded.tagRevision, 4)
    }

    func testCorruptIndexFailsDecodingRatherThanResetting() {
        XCTAssertThrowsError(try JSONDecoder().decode(IndexSnapshot.self, from: Data("{}".utf8)))
    }
}
