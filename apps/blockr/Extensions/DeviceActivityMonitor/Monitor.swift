import DeviceActivity
import Foundation
final class Monitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        try? Enforcement.reconcile()
    }
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        try? Enforcement.reconcile(monitorEnded: UUID(uuidString: activity.rawValue))
    }
}
