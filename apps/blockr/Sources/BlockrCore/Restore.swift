import Foundation

/// Recovery never changes an immutable lock's start or end.
public enum Restore {
    // Persistent OS store identity: changing this would abandon installed shields.
    public static let managedSettingsStoreName = "blockr"
    public enum Authorization: Equatable, Sendable { case approved, notDetermined, denied }
    public enum Action: Equatable, Sendable {
        case reapply(UUID)
        case reschedule(Lock)
        case notProtected(UUID)
    }
    public static func plan(locks: [Lock], receipts: [Receipt], snapshotsPresent: Set<UUID>,
                            monitoredIDs: Set<UUID>, authorization: Authorization, now: Date) -> [Action] {
        locks.filter { $0.isLive(at: now) }.flatMap { lock -> [Action] in
            guard authorization != .denied, snapshotsPresent.contains(lock.id) else {
                return [.notProtected(lock.id)]
            }
            guard receipts.contains(where: { $0.lockID == lock.id && $0.hasInstalledCoverage }) else { return [] }
            var actions: [Action] = [.reapply(lock.id)]
            if !monitoredIDs.contains(lock.id) { actions.append(.reschedule(lock)) }
            return actions
        }
    }
}
