import Foundation
import XCTest
@testable import ShotrCore

final class SearchEngineTests: XCTestCase {
    func testPreparedSearchPreservesSemanticsAndRefreshesRenamedTags() {
        var tag = Tag(name: "Travel")
        let record = Screenshot(id: "photo", createdAt: .distantPast, title: "Café",
                                text: "TABLE 12 東京", visualLabels: ["Restaurant"], aiTagIDs: [tag.id])
        let prepared = SearchEngine.prepare(record, tags: [tag])
        for query in ["CAFE table travel restaurant", "東京", "absent", " \n "] {
            for filter in [TagFilter.all, .untagged, .tag(tag.id), .tag(UUID())] {
                XCTAssertEqual(prepared.matches(query: query, filter: filter),
                               SearchEngine.matches(record, tags: [tag], query: query, filter: filter))
            }
        }
        XCTAssertEqual(prepared.effectiveTagIDs, [tag.id])
        tag.name = "Holidays"
        let refreshed = PreparedSearchDocument(record: record, tags: [tag])
        XCTAssertTrue(refreshed.matches(query: "holidays", filter: .tag(tag.id)))
        XCTAssertFalse(refreshed.matches(query: "travel", filter: .all))
        XCTAssertTrue(prepared.matches(query: "travel", filter: .all))
        XCTAssertFalse(prepared.matches(query: "holidays", filter: .all))
    }

    func testSearchMatchesAllWordsAcrossFieldsIgnoringAccentsCaseAndWidth() {
        let tag = Tag(name: "Travel")
        let record = Screenshot(id: "photo", createdAt: .distantPast, title: "Café in Tokyo",
                                text: "Book TABLE 12 東京", visualLabels: ["Restaurant"], aiTagIDs: [tag.id])
        XCTAssertTrue(SearchEngine.matches(record, tags: [tag], query: "CAFE table travel restaurant", filter: .all))
        XCTAssertTrue(SearchEngine.matches(record, tags: [tag], query: "ｔｏｋｙｏ 東京", filter: .tag(tag.id)))
        XCTAssertFalse(SearchEngine.matches(record, tags: [tag], query: "cafe flight", filter: .all))
        XCTAssertTrue(SearchEngine.matches(record, tags: [tag], query: " \n\t ", filter: .all))
    }

    func testRenamedTagSearchUsesCurrentNameAndStableID() {
        var tag = Tag(name: "Travel")
        let record = Screenshot(id: "photo", createdAt: .distantPast, aiTagIDs: [tag.id])
        tag.name = "Holidays"
        XCTAssertTrue(SearchEngine.matches(record, tags: [tag], query: "holidays", filter: .tag(tag.id)))
        XCTAssertFalse(SearchEngine.matches(record, tags: [tag], query: "travel", filter: .all))
        XCTAssertFalse(SearchEngine.matches(record, tags: [], query: "holidays", filter: .all))
    }

    func testTagFilterAndQueryBothApply() {
        let selected = Tag(name: "Events"), other = Tag(name: "Work")
        let record = Screenshot(id: "photo", createdAt: .distantPast, text: "CRSSD Saturday", aiTagIDs: [selected.id])
        XCTAssertTrue(SearchEngine.matches(record, tags: [selected, other], query: "saturday", filter: .tag(selected.id)))
        XCTAssertFalse(SearchEngine.matches(record, tags: [selected, other], query: "saturday", filter: .tag(other.id)))
        XCTAssertFalse(SearchEngine.matches(record, tags: [selected, other], query: "sunday", filter: .tag(selected.id)))
        XCTAssertFalse(SearchEngine.matches(record, tags: [selected, other], query: "", filter: .untagged))
    }

    func testUntaggedRespectsManualRemovalsAndDeletedTags() {
        let tag = Tag(name: "Shopping")
        var record = Screenshot(id: "photo", createdAt: .distantPast, aiTagIDs: [tag.id])
        XCTAssertTrue(SearchEngine.matches(record, tags: [], query: "", filter: .untagged))
        XCTAssertFalse(SearchEngine.matches(record, tags: [], query: "", filter: .tag(tag.id)))
        TagRules.set(tagID: tag.id, assigned: false, on: &record)
        XCTAssertTrue(SearchEngine.matches(record, tags: [tag], query: "", filter: .untagged))
        XCTAssertFalse(SearchEngine.matches(record, tags: [tag], query: "shopping", filter: .all))
    }
}
