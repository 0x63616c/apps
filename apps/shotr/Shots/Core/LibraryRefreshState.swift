import Foundation

/// Only metadata that affects screenshot membership, ordering or indexed content.
/// Photos also reports resource delivery, favorites and other irrelevant changes.
public struct PhotoItem: Equatable, Sendable {
    public var id: String
    public var createdAt: Date
    public var modifiedAt: Date?

    public init(id: String, createdAt: Date, modifiedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public enum ScreenshotSnapshotChange {
    public static func isRelevant(previous: [PhotoItem]?, fetched: [PhotoItem]) -> Bool {
        // A first snapshot must reconcile the persisted index, even if empty.
        guard let previous else { return true }
        return previous != fetched
    }
}

/// A refresh owns a snapshot only until the next library/lifecycle invalidation.
/// This is separate from scan cancellation: Pause must not discard new Photos data.
public struct LibraryRefreshGeneration: Sendable {
    public private(set) var current: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func invalidate() -> UInt64 {
        current &+= 1
        return current
    }

    public func accepts(_ token: UInt64, cancelled: Bool) -> Bool {
        !cancelled && token == current
    }
}

public enum ScanPauseReason: Equatable, Sendable {
    case user, system, storage, authorization
}
