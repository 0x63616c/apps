import Foundation
import BlockrCore

struct Attempt: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var lockIDs: [UUID]
}
struct LocalState: Codable {
    var replica = Replica()
    var selections: [String: Data] = [:]
    var snapshots: [String: Data] = [:]
    var receipts: [Receipt] = []
    var attempts: [Attempt] = []
    var previousDenyRemoval: Bool?
    var removalWasCaptured = false
    var detachedLockIDs: [UUID] = []
    var accountID: String?
    var accountHasBeenLinked = false
    var onboardingComplete = false
    var syncEnabled = true
    var deviceID = UUID().uuidString
    var lastSync: Date?
    mutating func receipt(_ lock: Lock, _ coverage: Coverage, now: Date = Date()) {
        let previous = receipts.first { $0.lockID == lock.id }
        let interrupted = previous?.interruptionObserved == true || [.failed, .interrupted].contains(coverage)
        let applied = previous?.appliedAt ?? ([.active, .partial].contains(coverage) ? now : nil)
        receipts.removeAll { $0.lockID == lock.id }
        receipts.append(Receipt(lockID: lock.id, coverage: coverage, acknowledged: now, interruptionObserved: interrupted, appliedAt: applied))
    }
}

/// All app/extension read-modify-writes share a coordinated, atomically replaced file.
/// Tokens and enforcement receipts never leave this file via sync.
enum Storage {
    static let appGroup = "group.com.calumwebb.blockr"
    static var file: URL {
        get throws {
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                throw BlockrError.unavailable("Blockr’s shared storage is unavailable. Reinstall a signed build.")
            }
            return container.appendingPathComponent("state.json")
        }
    }
    @discardableResult static func update<T>(_ body: (inout LocalState) throws -> T) throws -> T {
        let url = try file
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
            result = Result {
                var state: LocalState
                if FileManager.default.fileExists(atPath: coordinated.path) {
                    // Corruption is actionable; never overwrite it with an empty unlocked state.
                    state = try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: coordinated))
                } else { state = LocalState() }
                let value = try body(&state)
                try JSONEncoder().encode(state).write(to: coordinated, options: .atomic)
                return value
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BlockrError.unavailable("Shared storage could not be opened.") }
        return try result.get()
    }
    static func read() throws -> LocalState {
        let url = try file
        var coordinationError: NSError?
        var result: Result<LocalState, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result {
                if !FileManager.default.fileExists(atPath: coordinated.path) { return LocalState() }
                return try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: coordinated))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BlockrError.unavailable("Shared storage could not be read.") }
        return try result.get()
    }
}
