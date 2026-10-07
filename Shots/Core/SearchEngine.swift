import Foundation

/// A search snapshot; rebuild when the screenshot or tag taxonomy changes.
public struct PreparedSearchDocument: Sendable {
    public let normalizedText: String
    public let effectiveTagIDs: Set<UUID>
    public let isFavorite: Bool

    public init(record: Screenshot, tags: [Tag]) {
        let effective = TagRules.effectiveTags(for: record, allowed: Set(tags.map(\.id)))
        effectiveTagIDs = effective
        isFavorite = record.favoritedAt != nil
        let tagNames = tags.filter { effective.contains($0.id) }.map(\.name)
        let fields = [record.title, record.text, record.contentDescription ?? "", isFavorite ? "Favorites" : ""] + record.visualLabels + tagNames
        normalizedText = SearchNormalization.fold(fields.joined(separator: "\n"))
    }

    public func matches(query: String, filter: TagFilter) -> Bool {
        switch filter {
        case .all: break
        case .favorites: guard isFavorite else { return false }
        case .untagged:
            guard effectiveTagIDs.isEmpty else { return false }
        case .tag(let id):
            guard effectiveTagIDs.contains(id) else { return false }
        }
        let terms = SearchNormalization.fold(query).split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return true }
        return terms.allSatisfy { normalizedText.contains($0) }
    }
}

public enum SearchEngine {
    public static func prepare(_ record: Screenshot, tags: [Tag]) -> PreparedSearchDocument {
        PreparedSearchDocument(record: record, tags: tags)
    }

    public static func matches(
        _ record: Screenshot,
        tags: [Tag],
        query: String,
        filter: TagFilter
    ) -> Bool {
        prepare(record, tags: tags).matches(query: query, filter: filter)
    }
}
