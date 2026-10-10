import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The last good remote feed, stored as JSON on disk with its ETag so the app works offline.
struct FeedCache: Sendable {
    struct Entry: Codable, Sendable {
        var etag: String?
        var fetchedAt: Date
        var sourceURL: URL
    }

    var directory: URL

    static var standard: FeedCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FeedCache(directory: base.appendingPathComponent("FeedCache", isDirectory: true))
    }

    private var feedURL: URL { directory.appendingPathComponent("feed.json") }
    private var entryURL: URL { directory.appendingPathComponent("feed-meta.json") }

    func load() -> (feed: Feed, entry: Entry)? {
        guard let data = try? Data(contentsOf: feedURL),
              let feed = try? Feed.decode(data),
              let metaData = try? Data(contentsOf: entryURL),
              let entry = try? FeedCoding.decoder.decode(Entry.self, from: metaData) else { return nil }
        return (feed, entry)
    }

    func save(_ data: Data, entry: Entry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: feedURL, options: .atomic)
        try FeedCoding.encoder.encode(entry).write(to: entryURL, options: .atomic)
    }

    func touch(_ entry: Entry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FeedCoding.encoder.encode(entry).write(to: entryURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum FeedFetchResult: Sendable {
    case updated(Feed, Data, etag: String?)
    case notModified
}

struct FeedClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    var transport: Transport

    static let live = FeedClient { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    func fetch(_ url: URL, etag: String?) async throws -> FeedFetchResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await transport(request)
        switch response.statusCode {
        case 304:
            return .notModified
        case 200..<300:
            let feed = try Feed.decode(data)
            return .updated(feed, data, etag: response.value(forHTTPHeaderField: "ETag"))
        default:
            throw URLError(.badServerResponse)
        }
    }
}

enum FeedSelection {
    /// Prefer the cached remote feed unless the bundled seed is newer (for example after an app update).
    static func best(seed: Feed, cached: Feed?) -> Feed {
        guard let cached, cached.schemaVersion <= Feed.supportedSchemaVersion else { return seed }
        return cached.generatedAt >= seed.generatedAt ? cached : seed
    }
}
