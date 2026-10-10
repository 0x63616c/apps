import Foundation
import Observation

/// Launch-time switches. `--screenshots` pins the clock to Saturday evening at Head Trip with a
/// prepared schedule and no network, so captures are deterministic. `--reset` clears saved choices,
/// and `--now <ISO-8601>` pins the clock for UI tests.
struct AppEnvironment {
    var isScreenshotMode: Bool
    var resetState: Bool
    var fixedNow: Date?

    static let current: AppEnvironment = {
        let arguments = ProcessInfo.processInfo.arguments
        let screenshots = arguments.contains("--screenshots")
        let pinned = arguments.firstIndex(of: "--now").flatMap { index in
            arguments.indices.contains(index + 1) ? FeedCoding.parseInstant(arguments[index + 1]) : nil
        }
        return AppEnvironment(
            isScreenshotMode: screenshots,
            resetState: arguments.contains("--reset") || screenshots,
            fixedNow: pinned ?? (screenshots ? FeedCoding.parseInstant("2026-10-11T03:05:00Z") : nil)
        )
    }()
}

enum FeedConfiguration {
    static let overrideKey = "feedBaseURL"

    /// `<base>/feed/index.json`, where base is the `feedBaseURL` user default (About, or `-feedBaseURL <url>`
    /// at launch), otherwise the `FEED_BASE_URL` Info.plist value. Unset means the bundled feed only.
    static var remoteURL: URL? {
        let override = UserDefaults.standard.string(forKey: overrideKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        let bundled = Bundle.main.object(forInfoDictionaryKey: "FEED_BASE_URL") as? String ?? ""
        return FeedEndpoint.indexURL(base: override.isEmpty ? bundled : override)
    }

    static func seedFeed() -> Feed {
        guard let url = Bundle.main.url(forResource: "seed-feed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let feed = try? Feed.decode(data) else {
            return Feed(schemaVersion: Feed.supportedSchemaVersion, generatedAt: .distantPast, festivals: [])
        }
        return feed
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var feed: Feed
    private(set) var lastChecked: Date?
    private(set) var isRefreshing = false
    private(set) var refreshFailed = false
    var showFavouritesOnly = false

    private(set) var favourites: Set<String>
    private(set) var chosenSetIDs: Set<String>

    let environment: AppEnvironment
    private let seed: Feed
    private let cache: FeedCache
    private let client: FeedClient
    private let defaults: UserDefaults

    private enum Keys {
        static let favourites = "favouriteFestivals"
        static let chosen = "chosenSets"
    }

    init(environment: AppEnvironment = .current, cache: FeedCache = .standard, client: FeedClient = .live, defaults: UserDefaults = .standard) {
        let seedFeed = FeedConfiguration.seedFeed()
        if environment.resetState {
            defaults.removeObject(forKey: Keys.favourites)
            defaults.removeObject(forKey: Keys.chosen)
        }
        self.environment = environment
        self.cache = cache
        self.client = client
        self.defaults = defaults
        seed = seedFeed

        if environment.isScreenshotMode {
            feed = seedFeed
            favourites = ["head-trip-2026"]
            let headTrip = seedFeed.festival(id: "head-trip-2026")
            let sunday = LocalDate(year: 2026, month: 10, day: 11)
            chosenSetIDs = Set(headTrip?.sets
                .filter { Self.screenshotPicks.contains($0.artist) && !($0.stageId == "sunflower" && headTrip?.day(of: $0) == sunday) }
                .map(\.id) ?? [])
            lastChecked = nil
        } else {
            let cached = cache.load()
            feed = FeedSelection.best(seed: seedFeed, cached: cached?.feed)
            lastChecked = cached?.entry.fetchedAt
            favourites = Set(defaults.stringArray(forKey: Keys.favourites) ?? [])
            chosenSetIDs = Set(defaults.stringArray(forKey: Keys.chosen) ?? [])
        }
    }

    /// Saturday picks include the Sunflower stage so the clash highlight is visible.
    private static let screenshotPicks: Set<String> = [
        "Seth Troxler b2b Ben Sterling", "Peggy Gou b2b Four Tet", "Under Construction (FISHER + Chris Lake)",
        "Calvin Harris", "Floating Points Sunflower Sound System",
        "DJ Harvey", "Dom Dolla b2b KETTAMA", "Skrillex", "Swedish House Mafia"
    ]

    func now() -> Date { environment.fixedNow ?? Date() }

    // MARK: Festivals

    var upcomingFestivals: [Festival] {
        let now = now()
        return feed.festivals
            .filter { $0.isUpcomingOrLive(now: now) }
            .sorted { ($0.startDate, $0.name) < ($1.startDate, $1.name) }
    }

    var visibleFestivals: [Festival] {
        showFavouritesOnly ? upcomingFestivals.filter { favourites.contains($0.id) } : upcomingFestivals
    }

    func festival(id: String) -> Festival? { feed.festival(id: id) }

    func isFavourite(_ festival: Festival) -> Bool { favourites.contains(festival.id) }

    func toggleFavourite(_ festival: Festival) {
        if favourites.contains(festival.id) { favourites.remove(festival.id) } else { favourites.insert(festival.id) }
        persist(favourites, key: Keys.favourites)
    }

    // MARK: Schedule

    func isChosen(_ set: FestivalSet) -> Bool { chosenSetIDs.contains(set.id) }

    func toggle(_ set: FestivalSet) {
        if chosenSetIDs.contains(set.id) { chosenSetIDs.remove(set.id) } else { chosenSetIDs.insert(set.id) }
        persist(chosenSetIDs, key: Keys.chosen)
    }

    func chosenSets(in festival: Festival) -> [FestivalSet] {
        festival.sets.filter { chosenSetIDs.contains($0.id) }.sorted(by: FestivalSet.chronological)
    }

    func chosenSets(in festival: Festival, on day: LocalDate) -> [FestivalSet] {
        festival.sets(on: day).filter { chosenSetIDs.contains($0.id) }
    }

    /// Festivals with chosen sets first, then favourites with set times, by date.
    var scheduleFestivals: [Festival] {
        let withPicks = upcomingFestivals.filter { !chosenSets(in: $0).isEmpty }
        let favouritesWithTimes = upcomingFestivals.filter { favourites.contains($0.id) && $0.hasSetTimes && !withPicks.contains($0) }
        return withPicks + favouritesWithTimes
    }

    // MARK: Feed

    var feedURL: URL? { environment.isScreenshotMode ? nil : FeedConfiguration.remoteURL }

    func refresh() async {
        guard let url = feedURL, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let previous = cache.load()
        let etag = previous?.entry.sourceURL == url ? previous?.entry.etag : nil
        do {
            switch try await client.fetch(url, etag: etag) {
            case let .updated(remote, data, newETag):
                let entry = FeedCache.Entry(etag: newETag, fetchedAt: Date(), sourceURL: url)
                try? cache.save(data, entry: entry)
                feed = FeedSelection.best(seed: seed, cached: remote)
                lastChecked = entry.fetchedAt
            case .notModified:
                if var entry = previous?.entry {
                    entry.fetchedAt = Date()
                    try? cache.touch(entry)
                    lastChecked = entry.fetchedAt
                }
            }
            refreshFailed = false
        } catch {
            refreshFailed = true
        }
    }

    func setFeedURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: FeedConfiguration.overrideKey)
        } else {
            defaults.set(trimmed, forKey: FeedConfiguration.overrideKey)
        }
        cache.clear()
        feed = seed
        lastChecked = nil
    }

    private func persist(_ ids: Set<String>, key: String) {
        guard !environment.isScreenshotMode else { return }
        defaults.set(ids.sorted(), forKey: key)
    }
}
