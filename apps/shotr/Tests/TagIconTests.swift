import Foundation
import XCTest
@testable import ShotrCore

final class TagIconTests: XCTestCase {
    func testLegacyTagDecodesWithoutLosingIDOrName() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id)\",\"name\":\"Travel\"}".utf8)
        let tag = try JSONDecoder().decode(Tag.self, from: data)
        XCTAssertEqual(tag.id, id)
        XCTAssertEqual(tag.name, "Travel")
        XCTAssertEqual(tag.icon.id, "airplane")
    }

    func testUnknownStoredSymbolUsesSafeFallback() throws {
        let data = Data("{\"id\":\"\(UUID())\",\"name\":\"Custom\",\"iconName\":\"invented.symbol\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(Tag.self, from: data).iconName, "tag")
    }

    func testCustomIconAndAssignmentsSurviveRenameAndRoundTrip() throws {
        var tag = Tag(name: "Trips", iconName: "beach.umbrella")
        let screenshot = Screenshot(id: "sample", createdAt: .distantPast, addedTagIDs: [tag.id])
        tag.name = "Weekends"
        let saved = IndexSnapshot(tags: [tag], screenshots: [screenshot])
        let decoded = try JSONDecoder().decode(IndexSnapshot.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.tags, [tag])
        XCTAssertEqual(decoded.tags[0].icon.id, "beach.umbrella")
        XCTAssertEqual(TagRules.effectiveTags(for: decoded.screenshots[0], allowed: [tag.id]), [tag.id])
    }

    func testCatalogHasUniqueSymbolsAndReadableAIContext() {
        XCTAssertEqual(TagIcon.all.count, 64)
        XCTAssertEqual(Set(TagIcon.all.map(\.id)).count, TagIcon.all.count)
        XCTAssertTrue(TagIcon.all.allSatisfy { !$0.name.isEmpty && !$0.category.isEmpty })
        XCTAssertTrue(IndexSnapshot.defaultTags.allSatisfy { TagIcon.all.contains($0.icon) })
    }
}
