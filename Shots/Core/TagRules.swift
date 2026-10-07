import Foundation

public enum TagNameError: Error, LocalizedError, Equatable {
    case empty
    case tooLong
    case duplicate

    public var errorDescription: String? {
        switch self {
        case .empty: "Enter a tag name."
        case .tooLong: "Use 32 characters or fewer."
        case .duplicate: "That tag already exists."
        }
    }
}

public enum TagRules {
    /// Sample across the library's date range rather than only its newest images.
    public static func discoverySample(records: [Screenshot], limit: Int = 32) -> [String] {
        guard limit > 0 else { return [] }
        var ordered: [String] = []
        var counts: [String: Int] = [:]
        var originals: [String: String] = [:]
        for record in records.filter({ $0.hiddenAt == nil && $0.describedAt != nil })
            .sorted(by: { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt })
        {
            guard let description = record.contentDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !description.isEmpty else { continue }
            let key = SearchNormalization.fold(description)
            if counts[key] == nil { ordered.append(key); originals[key] = description }
            counts[key, default: 0] += 1
        }
        let descriptions = ordered.map { key in
            let count = counts[key] ?? 1
            let prefix = count > 1 ? "[\(count) screenshots] " : ""
            return String((prefix + (originals[key] ?? "")).prefix(240))
        }
        guard descriptions.count > limit else { return descriptions }
        if limit == 1 { return [descriptions[0]] }
        return (0..<limit).map { descriptions[$0 * (descriptions.count - 1) / (limit - 1)] }
    }

    public static func discoveryIsDue(count: Int, lastCount: Int?, completed: Bool) -> Bool {
        guard count >= 2 else { return false }
        guard let last = lastCount else { return true }
        if !completed { return count > last && count >= min(max(2, last * 2), last + 100) }
        return count - last >= 100
    }

    public static func categoriesToAdd(names: [String], existing: [Tag], dismissed: [String]) -> [Tag] {
        let excluded = Set(dismissed.map(SearchNormalization.fold))
        var result: [Tag] = []
        for name in names {
            guard existing.count + result.count < 32, result.count < 8 else { break }
            guard let valid = try? validatedName(name, tags: existing + result),
                  !excluded.contains(SearchNormalization.fold(valid)) else { continue }
            result.append(Tag(name: valid))
        }
        return result
    }

    /// Replace untouched starter categories only; user edits and manual intent win.
    public static func retireableDefaultIDs(tags: [Tag], records: [Screenshot]) -> Set<UUID> {
        let manual = records.reduce(into: Set<UUID>()) { $0.formUnion($1.addedTagIDs); $0.formUnion($1.removedTagIDs) }
        let defaults = Set(IndexSnapshot.defaultTags)
        return Set(tags.filter { defaults.contains($0) && !manual.contains($0.id) }.map(\.id))
    }

    /// Model output is an index into this request's taxonomy, never a stored ID.
    public static func suggestedIDs(indices: [Int], tags: [Tag]) -> Set<UUID> {
        // Enforce the generated schema's bound again at the trust boundary. An
        // invalid or duplicate index never becomes a new tag or a manual override.
        Set(indices.prefix(4).compactMap { tags.indices.contains($0) ? tags[$0].id : nil })
    }

    public static func effectiveTags(for record: Screenshot, allowed: Set<UUID>) -> Set<UUID> {
        record.aiTagIDs
            .union(record.addedTagIDs)
            .subtracting(record.removedTagIDs)
            .intersection(allowed)
    }

    /// Store intent even if AI currently agrees, so future scans cannot undo it.
    public static func set(tagID: UUID, assigned: Bool, on record: inout Screenshot) {
        if assigned {
            record.addedTagIDs.insert(tagID)
            record.removedTagIDs.remove(tagID)
        } else {
            record.removedTagIDs.insert(tagID)
            record.addedTagIDs.remove(tagID)
        }
    }

    public static func validatedName(_ input: String, tags: [Tag], excluding: UUID? = nil) throws -> String {
        let name = input.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !name.isEmpty else { throw TagNameError.empty }
        guard name.count <= 32 else { throw TagNameError.tooLong }
        let key = SearchNormalization.fold(name)
        guard !tags.contains(where: {
            $0.id != excluding && SearchNormalization.fold($0.name) == key
        }) else { throw TagNameError.duplicate }
        return name
    }

    /// Remove stale IDs from storage after deleting a tag.
    public static func prune(_ record: inout Screenshot, allowed: Set<UUID>) {
        record.aiTagIDs.formIntersection(allowed)
        record.addedTagIDs.formIntersection(allowed)
        record.removedTagIDs.formIntersection(allowed)
    }
}

enum SearchNormalization {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}
