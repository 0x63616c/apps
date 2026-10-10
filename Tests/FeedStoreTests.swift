import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FestrCore

final class FeedStoreTests: XCTestCase {
    static let url = URL(string: "https://festr.example/api/feed")!
    var url: URL { Self.url }

    static func response(_ status: Int, etag: String? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: Self.url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: etag.map { ["ETag": $0] })!
    }

    func testSendsTheETagAndHandlesNotModified() async throws {
        let client = FeedClient { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
            return (Data(), Self.response(304))
        }
        guard case .notModified = try await client.fetch(url, etag: "\"abc\"") else { return XCTFail("expected 304") }
    }

    func testDecodesAnUpdatedFeed() async throws {
        let body = try SeedFeed.load().encoded()
        let client = FeedClient { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            return (body, Self.response(200, etag: "\"v2\""))
        }
        guard case let .updated(feed, data, etag) = try await client.fetch(url, etag: nil) else { return XCTFail("expected 200") }
        XCTAssertEqual(etag, "\"v2\"")
        XCTAssertEqual(data, body)
        XCTAssertEqual(feed.festivals.first?.id, "head-trip-2026")
    }

    func testServerErrorsThrow() async {
        let client = FeedClient { _ in (Data(), Self.response(500)) }
        do {
            _ = try await client.fetch(url, etag: nil)
            XCTFail("expected an error")
        } catch {}
    }

    func testCacheRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeedCache(directory: directory)
        XCTAssertNil(cache.load())
        let data = try SeedFeed.load().encoded()
        let fetchedAt = FeedCoding.parseInstant("2026-10-10T20:00:00Z")!
        try cache.save(data, entry: .init(etag: "\"v1\"", fetchedAt: fetchedAt, sourceURL: url))
        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.entry.etag, "\"v1\"")
        XCTAssertEqual(loaded.entry.fetchedAt, fetchedAt)
        XCTAssertEqual(loaded.feed, try SeedFeed.load())
    }

    func testSelectionPrefersTheNewerFeed() throws {
        let seed = try SeedFeed.load()
        var remote = seed
        remote.generatedAt = seed.generatedAt.addingTimeInterval(3600)
        remote.festivals = []
        XCTAssertEqual(FeedSelection.best(seed: seed, cached: remote), remote)
        remote.generatedAt = seed.generatedAt.addingTimeInterval(-3600)
        XCTAssertEqual(FeedSelection.best(seed: seed, cached: remote), seed)
        XCTAssertEqual(FeedSelection.best(seed: seed, cached: nil), seed)
    }
}
