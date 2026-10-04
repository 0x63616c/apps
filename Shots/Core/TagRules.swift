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
