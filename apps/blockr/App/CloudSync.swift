import CloudKit
import Foundation
import BlockrCore

/// A private, optimistic-concurrency replica. Local state is the durable outbound queue;
/// save conflicts always merge the server replica before retrying. Token blobs are excluded by type.
actor CloudSync {
    enum Status: Equatable { case unavailable, off, signedOut, syncing, current, error(String) }
    private var busy = false
    private let zoneID = CKRecordZone.ID(zoneName: "Blockr")
    // Deliberately do not initialize CKContainer without signed entitlements: CloudKit can terminate a process.
    private var container: CKContainer?
    func synchronize() async -> Status {
        guard Bundle.main.object(forInfoDictionaryKey: "BlockrCloudEnabled") as? String == "YES" else { return .unavailable }
        guard !busy else { return .syncing }
        busy = true
        defer { busy = false }
        do {
            guard try Storage.read().syncEnabled else { return .off }
            let container = self.container ?? CKContainer(identifier: "iCloud.com.calumwebb.blockr")
            self.container = container
            guard try await container.accountStatus() == .available else { return .signedOut }
            let account = try await container.userRecordID().recordName
            // Never send one Apple Account's replica into another account's database.
            try Storage.update { state in
                if state.accountHasBeenLinked && state.accountID != account {
                    let live = state.replica.liveLocks(at: Date())
                    state.replica = Replica()
                    // Keep enforcement snapshots locally, but do not publish detached sessions.
                    state.replica.locks = live
                    state.detachedLockIDs = live.map(\.id)
                    state.selections.removeAll()
                    state.lastSync = nil
                }
                state.accountID = account
                state.accountHasBeenLinked = true
            }
            let database = container.privateCloudDatabase
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            let id = CKRecord.ID(recordName: "replica-v1", zoneID: zoneID)
            for attempt in 0..<4 {
                let record: CKRecord
                do { record = try await database.record(for: id) }
                catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "BlockrReplica", recordID: id) }
                let remote: Replica
                if let data = record["payload"] as? Data { remote = try JSONDecoder().decode(Replica.self, from: data) } else { remote = Replica() }
                let merged = try Storage.update { state -> Replica in
                    state.replica = state.replica.merging(remote)
                    // Active sessions from a detached account continue locally, but cannot enter this account.
                    var outbound = state.replica
                    outbound.locks.removeAll { lock in state.detachedLockIDs.contains(lock.id) || state.receipts.contains { $0.lockID == lock.id && $0.coverage == .failed } }
                    return outbound
                }
                let payload = try JSONEncoder().encode(merged)
                guard payload.count < 900_000 else { throw BlockrError.unavailable("iCloud history is full. Local protection still works.") }
                record["payload"] = payload as CKRecordValue
                do {
                    _ = try await database.save(record)
                    try Storage.update { $0.lastSync = Date() }
                    // Silent pushes are a best-effort wakeup, never a promise of instantaneous enforcement.
                    let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "blockr-zone")
                    let notification = CKSubscription.NotificationInfo()
                    notification.shouldSendContentAvailable = true
                    subscription.notificationInfo = notification
                    _ = try await database.save(subscription)
                    return .current
                } catch let error as CKError where error.code == .serverRecordChanged && attempt < 3 { continue }
            }
            return .error("iCloud changed during sync. Retry.")
        } catch { return .error(error.localizedDescription) }
    }
}
