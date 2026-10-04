import Foundation

public struct Tag: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var iconName: String
    public var icon: TagIcon { TagIcon.resolve(iconName, for: name) }

    public init(id: UUID = UUID(), name: String, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.iconName = TagIcon.resolve(iconName, for: name).id
    }

    private enum CodingKeys: String, CodingKey { case id, name, iconName }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        iconName = TagIcon.resolve(try values.decodeIfPresent(String.self, forKey: .iconName), for: name).id
    }
}

/// A shared, bounded vocabulary for people and model-facing tag context.
public struct TagIcon: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: String

    public static func resolve(_ symbol: String?, for name: String) -> TagIcon {
        if let icon = all.first(where: { $0.id == symbol }) { return icon }
        let defaults = ["shopping": "bag", "food": "fork.knife", "travel": "airplane",
                        "places": "mappin.and.ellipse", "events": "calendar", "messages": "bubble.left.and.bubble.right",
                        "work": "briefcase", "ideas": "lightbulb", "receipts": "receipt", "reading": "book"]
        let symbol = defaults[name.lowercased()] ?? "tag"
        return all.first(where: { $0.id == symbol }) ?? all[0]
    }

    public static let all: [TagIcon] = [
        TagIcon(id: "tag", name: "Tag", category: "Everyday"),
        TagIcon(id: "star", name: "Favorites", category: "Everyday"),
        TagIcon(id: "heart", name: "Love", category: "Everyday"),
        TagIcon(id: "bookmark", name: "Saved", category: "Everyday"),
        TagIcon(id: "flag", name: "Flag", category: "Everyday"),
        TagIcon(id: "checkmark.seal", name: "Verified", category: "Everyday"),
        TagIcon(id: "person", name: "People", category: "Everyday"),
        TagIcon(id: "person.2", name: "Friends", category: "Everyday"),
        TagIcon(id: "house", name: "Home", category: "Everyday"),
        TagIcon(id: "gift", name: "Gifts", category: "Everyday"),
        TagIcon(id: "bag", name: "Shopping", category: "Life"),
        TagIcon(id: "cart", name: "Groceries", category: "Life"),
        TagIcon(id: "fork.knife", name: "Food", category: "Life"),
        TagIcon(id: "cup.and.saucer", name: "Coffee", category: "Life"),
        TagIcon(id: "birthday.cake", name: "Celebrations", category: "Life"),
        TagIcon(id: "carrot", name: "Cooking", category: "Life"),
        TagIcon(id: "tshirt", name: "Clothing", category: "Life"),
        TagIcon(id: "pawprint", name: "Pets", category: "Life"),
        TagIcon(id: "leaf", name: "Nature", category: "Life"),
        TagIcon(id: "camera.macro", name: "Flowers", category: "Life"),
        TagIcon(id: "airplane", name: "Travel", category: "Places"),
        TagIcon(id: "mappin.and.ellipse", name: "Places", category: "Places"),
        TagIcon(id: "map", name: "Maps", category: "Places"),
        TagIcon(id: "car", name: "Driving", category: "Places"),
        TagIcon(id: "tram", name: "Transit", category: "Places"),
        TagIcon(id: "bicycle", name: "Cycling", category: "Places"),
        TagIcon(id: "mountain.2", name: "Outdoors", category: "Places"),
        TagIcon(id: "beach.umbrella", name: "Beach", category: "Places"),
        TagIcon(id: "building.2", name: "City", category: "Places"),
        TagIcon(id: "globe", name: "World", category: "Places"),
        TagIcon(id: "calendar", name: "Events", category: "Culture"),
        TagIcon(id: "ticket", name: "Tickets", category: "Culture"),
        TagIcon(id: "music.note", name: "Music", category: "Culture"),
        TagIcon(id: "headphones", name: "Audio", category: "Culture"),
        TagIcon(id: "film", name: "Movies", category: "Culture"),
        TagIcon(id: "gamecontroller", name: "Games", category: "Culture"),
        TagIcon(id: "book", name: "Reading", category: "Culture"),
        TagIcon(id: "newspaper", name: "News", category: "Culture"),
        TagIcon(id: "camera", name: "Photography", category: "Culture"),
        TagIcon(id: "paintpalette", name: "Art", category: "Culture"),
        TagIcon(id: "briefcase", name: "Work", category: "Work"),
        TagIcon(id: "lightbulb", name: "Ideas", category: "Work"),
        TagIcon(id: "doc.text", name: "Documents", category: "Work"),
        TagIcon(id: "receipt", name: "Receipts", category: "Work"),
        TagIcon(id: "creditcard", name: "Payments", category: "Work"),
        TagIcon(id: "chart.bar", name: "Charts", category: "Work"),
        TagIcon(id: "pencil", name: "Writing", category: "Work"),
        TagIcon(id: "laptopcomputer", name: "Technology", category: "Work"),
        TagIcon(id: "chevron.left.forwardslash.chevron.right", name: "Code", category: "Work"),
        TagIcon(id: "graduationcap", name: "Learning", category: "Work"),
        TagIcon(id: "bubble.left.and.bubble.right", name: "Messages", category: "Personal"),
        TagIcon(id: "envelope", name: "Mail", category: "Personal"),
        TagIcon(id: "phone", name: "Calls", category: "Personal"),
        TagIcon(id: "link", name: "Links", category: "Personal"),
        TagIcon(id: "lock", name: "Private", category: "Personal"),
        TagIcon(id: "key", name: "Keys", category: "Personal"),
        TagIcon(id: "clock", name: "Time", category: "Personal"),
        TagIcon(id: "bell", name: "Reminders", category: "Personal"),
        TagIcon(id: "dumbbell", name: "Fitness", category: "Personal"),
        TagIcon(id: "cross.case", name: "Health", category: "Personal"),
        TagIcon(id: "moon", name: "Rest", category: "Personal"),
        TagIcon(id: "sun.max", name: "Sunshine", category: "Personal"),
        TagIcon(id: "sparkles", name: "Inspiration", category: "Personal"),
        TagIcon(id: "square.grid.2x2", name: "Collections", category: "Personal"),
    ]
}

public struct Screenshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var createdAt: Date
    public var modifiedAt: Date?
    public var title: String
    public var text: String
    public var visualLabels: [String]
    public var aiTagIDs: Set<UUID>
    public var addedTagIDs: Set<UUID>
    public var removedTagIDs: Set<UUID>
    public var scannedAt: Date?
    public var taggedRevision: Int?
    public var lastError: String?
    public var hiddenAt: Date?

    public init(
        id: String,
        createdAt: Date,
        modifiedAt: Date? = nil,
        title: String = "",
        text: String = "",
        visualLabels: [String] = [],
        aiTagIDs: Set<UUID> = [],
        addedTagIDs: Set<UUID> = [],
        removedTagIDs: Set<UUID> = [],
        scannedAt: Date? = nil,
        taggedRevision: Int? = nil,
        lastError: String? = nil,
        hiddenAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.title = title
        self.text = text
        self.visualLabels = visualLabels
        self.aiTagIDs = aiTagIDs
        self.addedTagIDs = addedTagIDs
        self.removedTagIDs = removedTagIDs
        self.scannedAt = scannedAt
        self.taggedRevision = taggedRevision
        self.lastError = lastError
        self.hiddenAt = hiddenAt
    }
}

public struct IndexSnapshot: Codable, Sendable {
    public var version: Int
    public var tagRevision: Int
    public var tags: [Tag]
    public var screenshots: [Screenshot]

    public init(
        version: Int = 1,
        tagRevision: Int = 1,
        tags: [Tag] = IndexSnapshot.defaultTags,
        screenshots: [Screenshot] = []
    ) {
        self.version = version
        self.tagRevision = tagRevision
        self.tags = tags
        self.screenshots = screenshots
    }

    public static let defaultTags: [Tag] = [
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, name: "Shopping"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!, name: "Food"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!, name: "Travel"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000004")!, name: "Places"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!, name: "Events"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000006")!, name: "Messages"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000007")!, name: "Work"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000008")!, name: "Ideas"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000009")!, name: "Receipts"),
        Tag(id: UUID(uuidString: "10000000-0000-4000-8000-000000000010")!, name: "Reading")
    ]
}

public enum TagFilter: Hashable, Sendable {
    case all
    case untagged
    case tag(UUID)
}

public enum LibraryLayout: String, CaseIterable, Identifiable {
    case continuous = "Continuous grid", byDay = "Grouped by day"
    public var id: String { rawValue }
}

public struct ScreenshotDay: Identifiable {
    public let id: Date
    public let screenshots: [Screenshot]

    public static func groups(_ screenshots: [Screenshot], calendar: Calendar = .current) -> [ScreenshotDay] {
        Dictionary(grouping: screenshots, by: { calendar.startOfDay(for: $0.createdAt) })
            .sorted { $0.key > $1.key }
            .map { ScreenshotDay(id: $0.key, screenshots: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }
}

/// Active scan time only. No screenshot text or identifiers are recorded here.
public struct ScanMeasurement: Codable, Equatable, Sendable {
    public var completed = 0
    public var failed = 0
    public var elapsed: TimeInterval = 0
    public var imageSeconds: TimeInterval = 0
    public var analysisSeconds: TimeInterval = 0
    public var taggingSeconds: TimeInterval = 0
    public var aiAvailable = false

    public init() {}

    public func estimatedRemaining(total: Int, elapsed: TimeInterval) -> TimeInterval? {
        guard completed >= 3, total > completed, elapsed > 0 else { return nil }
        return elapsed / Double(completed) * Double(total - completed)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return value < 60 ? "\(value)s" : "\(value / 60)m \(value % 60)s"
    }
}
