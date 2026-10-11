import Foundation

/// Versioned festival feed. The app bundles a seed copy and refreshes it from `FeedConfiguration.remoteURL`.
/// Instants are UTC ISO-8601; festival dates are local dates in the festival's IANA `timeZone`.
struct Feed: Codable, Hashable, Sendable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    var generatedAt: Date
    var festivals: [Festival]

    static func decode(_ data: Data) throws -> Feed {
        let feed = try FeedCoding.decoder.decode(Feed.self, from: data)
        guard feed.schemaVersion <= supportedSchemaVersion else {
            throw FeedError.unsupportedSchema(feed.schemaVersion)
        }
        return feed
    }

    func encoded() throws -> Data {
        try FeedCoding.encoder.encode(self)
    }

    func festival(id: String) -> Festival? {
        festivals.first { $0.id == id }
    }
}

enum FeedError: Error, Equatable {
    case unsupportedSchema(Int)
    case unknownTimeZone(String)
}

struct Stage: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var sortOrder: Int

    init(id: String, name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

struct FestivalSet: Codable, Hashable, Sendable, Identifiable {
    /// Open-ended closers (no published end) are assumed to run this long for progress and clash checks.
    static let assumedOpenEndDuration: TimeInterval = 90 * 60

    var id: String
    var artist: String
    var stageId: String
    /// Festival day this set belongs to. When absent it is derived from `start` (see `Festival.day(of:)`).
    var day: LocalDate?
    var start: Date
    /// `nil` for an open-ended closer.
    var end: Date?
    var sourceURL: URL?
    var updatedAt: Date

    init(id: String, artist: String, stageId: String, day: LocalDate? = nil, start: Date, end: Date?, sourceURL: URL? = nil, updatedAt: Date) {
        self.id = id
        self.artist = artist
        self.stageId = stageId
        self.day = day
        self.start = start
        self.end = end
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, artist, stageId, day, start, end, sourceURL, updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(artist, forKey: .artist)
        try container.encode(stageId, forKey: .stageId)
        try container.encodeIfPresent(day, forKey: .day)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var isOpenEnded: Bool { end == nil }

    /// The published end, or the assumed end for an open-ended closer.
    var effectiveEnd: Date { end ?? start.addingTimeInterval(Self.assumedOpenEndDuration) }

    var interval: DateInterval { DateInterval(start: start, end: max(start, effectiveEnd)) }

    func isPlaying(at instant: Date) -> Bool {
        instant >= start && instant < effectiveEnd
    }

    func overlaps(_ other: FestivalSet) -> Bool {
        start < other.effectiveEnd && other.start < effectiveEnd
    }
}

struct FestivalLinks: Codable, Hashable, Sendable {
    var website: URL?
    var tickets: URL?

    init(website: URL? = nil, tickets: URL? = nil) {
        self.website = website
        self.tickets = tickets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        website = try? container.decodeIfPresent(URL.self, forKey: .website)
        tickets = try? container.decodeIfPresent(URL.self, forKey: .tickets)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(website, forKey: .website)
        try container.encode(tickets, forKey: .tickets)
    }

    enum CodingKeys: String, CodingKey { case website, tickets }
}

struct Festival: Codable, Hashable, Sendable, Identifiable {
    /// A set starting before this local hour belongs to the previous festival day (after-midnight sets).
    static let dayRolloverHour = 6

    var id: String
    var name: String
    var venue: String
    var city: String
    var region: String
    var country: String
    var timeZoneIdentifier: String
    var startDate: LocalDate
    var endDate: LocalDate
    var sourceURL: URL?
    var links: FestivalLinks
    var updatedAt: Date
    /// Announced artists, including those without published set times.
    var lineup: [String]
    var stages: [Stage]
    var sets: [FestivalSet]

    enum CodingKeys: String, CodingKey {
        case id, name, venue, city, region, country
        case timeZoneIdentifier = "timeZone"
        case startDate, endDate, sourceURL, links, updatedAt, lineup, stages, sets
    }

    init(id: String, name: String, venue: String, city: String, region: String, country: String = "US",
         timeZoneIdentifier: String, startDate: LocalDate, endDate: LocalDate, sourceURL: URL? = nil,
         links: FestivalLinks = FestivalLinks(), updatedAt: Date, lineup: [String] = [], stages: [Stage] = [], sets: [FestivalSet] = []) {
        self.id = id
        self.name = name
        self.venue = venue
        self.city = city
        self.region = region
        self.country = country
        self.timeZoneIdentifier = timeZoneIdentifier
        self.startDate = startDate
        self.endDate = endDate
        self.sourceURL = sourceURL
        self.links = links
        self.updatedAt = updatedAt
        self.lineup = lineup
        self.stages = stages
        self.sets = sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        venue = try container.decodeIfPresent(String.self, forKey: .venue) ?? ""
        city = try container.decode(String.self, forKey: .city)
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? "US"
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw FeedError.unknownTimeZone(timeZoneIdentifier)
        }
        startDate = try container.decode(LocalDate.self, forKey: .startDate)
        endDate = try container.decode(LocalDate.self, forKey: .endDate)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        links = try container.decodeIfPresent(FestivalLinks.self, forKey: .links) ?? FestivalLinks()
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lineup = try container.decodeIfPresent([String].self, forKey: .lineup) ?? []
        stages = try container.decodeIfPresent([Stage].self, forKey: .stages) ?? []
        sets = try container.decodeIfPresent([FestivalSet].self, forKey: .sets) ?? []
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    var location: String { region.isEmpty ? city : "\(city), \(region)" }

    var hasSetTimes: Bool { !sets.isEmpty }

    func stage(id: String) -> Stage? { stages.first { $0.id == id } }

    func stageName(for set: FestivalSet) -> String { stage(id: set.stageId)?.name ?? set.stageId }

    /// The festival day a set belongs to: its explicit `day`, otherwise the local date of its start,
    /// with sets starting before 06:00 counted on the previous day.
    func day(of set: FestivalSet) -> LocalDate {
        if let day = set.day { return day }
        let local = LocalDate(set.start, in: timeZone)
        let hour = Calendar.gregorian(timeZone).component(.hour, from: set.start)
        return hour < Self.dayRolloverHour ? local.adding(days: -1) : local
    }

    /// Every day from `startDate` to `endDate`, plus any day a set falls on outside that range.
    var days: [LocalDate] {
        var result: [LocalDate] = []
        var cursor = startDate
        while cursor <= endDate && result.count < 31 {
            result.append(cursor)
            cursor = cursor.adding(days: 1)
        }
        for set in sets where !result.contains(day(of: set)) {
            result.append(day(of: set))
        }
        return result.sorted()
    }

    func sets(on day: LocalDate) -> [FestivalSet] {
        sets.filter { self.day(of: $0) == day }.sorted(by: FestivalSet.chronological)
    }

    /// Stages with at least one set on `day`, in feed order.
    func stages(on day: LocalDate) -> [Stage] {
        let ids = Set(sets(on: day).map(\.stageId))
        return stages.filter { ids.contains($0.id) }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// Calendar days from today (in the festival's time zone) until the first day. 0 during the festival.
    func daysUntil(now: Date) -> Int {
        let today = LocalDate(now, in: timeZone)
        if today >= startDate && today <= endDate { return 0 }
        return today.days(until: startDate)
    }

    func isUpcomingOrLive(now: Date) -> Bool {
        LocalDate(now, in: timeZone) <= endDate
    }

    func isLive(now: Date) -> Bool {
        let today = LocalDate(now, in: timeZone)
        return today >= startDate && today <= endDate
    }

    /// The festival day happening at `now`, counting the early hours as part of the previous day.
    func festivalDay(at now: Date) -> LocalDate? {
        let local = LocalDate(now, in: timeZone)
        let hour = Calendar.gregorian(timeZone).component(.hour, from: now)
        let day = hour < Self.dayRolloverHour ? local.adding(days: -1) : local
        return days.contains(day) ? day : nil
    }
}

extension FestivalSet {
    static func chronological(_ lhs: FestivalSet, _ rhs: FestivalSet) -> Bool {
        (lhs.start, lhs.artist) < (rhs.start, rhs.artist)
    }
}

enum FeedCoding {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseInstant(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO-8601 instant, got \(raw)")
            }
            return date
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatInstant(date))
        }
        return encoder
    }

    /// Accepts `2026-10-10T23:30:00Z`, fractional seconds and explicit offsets.
    static func parseInstant(_ raw: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }

    static func formatInstant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
