import DeviceActivity
import Foundation
final class Monitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        try? Enforcement.reconcile()
        if let id = UUID(uuidString: activity.rawValue),
           let lock = try? Storage.read().replica.locks.first(where: { $0.id == id }) {
            LockNotificationCenter.schedule(lock)
        }
    }
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let id = UUID(uuidString: activity.rawValue)
        let before = try? Storage.read()
        try? Enforcement.reconcile(monitorEnded: id)
        if let id, let state = before,
           let lock = state.replica.locks.first(where: { $0.id == id }),
           state.receipts.contains(where: { $0.lockID == id && ($0.hasInstalledCoverage || $0.coverage == .completed) }) {
            LockNotificationCenter.ended(lock)
        }
    }
}
