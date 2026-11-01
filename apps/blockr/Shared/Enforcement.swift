#if os(iOS)
import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import BlockrCore

/// One named store belongs exclusively to Blockr. The union is recomputed on every boundary.
enum Enforcement {
    static let store = ManagedSettingsStore(named: .init("blockr"))
    static let center = DeviceActivityCenter()
    static func selection(_ data: Data?) -> FamilyActivitySelection {
        guard let data, let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return FamilyActivitySelection() }
        return value
    }
    static func hasSelection(_ value: FamilyActivitySelection) -> Bool {
        !value.applicationTokens.isEmpty || !value.categoryTokens.isEmpty || !value.webDomainTokens.isEmpty
    }
    static func schedule(_ lock: Lock, now: Date) throws {
        guard lock.remaining(at: now) >= 900 else { throw BlockrError.unavailable("Less than 15 minutes remain. This device cannot install that lock.") }
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(components, from: now), intervalEnd: calendar.dateComponents(components, from: lock.end), repeats: false)
        try center.startMonitoring(DeviceActivityName(lock.id.uuidString), during: schedule)
    }
    static func apply(_ state: inout LocalState, now: Date) throws {
        let live = state.replica.liveLocks(at: now).filter { lock in
            state.snapshots[lock.id.uuidString] != nil && state.receipts.contains { $0.lockID == lock.id && ($0.coverage == .active || $0.coverage == .partial || $0.coverage == .pending) }
        }
        if live.isEmpty {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = nil
            if let previous = state.previousDenyRemoval { store.application.denyAppRemoval = previous; state.previousDenyRemoval = nil }
            return
        }
        if state.previousDenyRemoval == nil { state.previousDenyRemoval = store.application.denyAppRemoval ?? false }
        var apps = Set<ApplicationToken>(), categories = Set<ActivityCategoryToken>(), websites = Set<WebDomainToken>(), domains = Set<WebDomain>()
        for lock in live {
            let picks = selection(state.snapshots[lock.id.uuidString])
            apps.formUnion(picks.applicationTokens)
            categories.formUnion(picks.categoryTokens)
            websites.formUnion(picks.webDomainTokens)
            domains.formUnion(lock.group.domains.map { WebDomain(domain: $0) })
        }
        guard apps.count <= 50, categories.count <= 50, websites.count <= 50, domains.count <= 50 else { throw BlockrError.unavailable("This combined lock exceeds the system’s 50-item limit.") }
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = websites.isEmpty ? nil : websites
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
        store.webContent.blockedByFilter = domains.isEmpty ? nil : .specific(domains)
        store.application.denyAppRemoval = true
    }
    static func reconcile(now: Date = Date(), monitorEnded: UUID? = nil) throws {
        try Storage.update { state in
            let authorized = AuthorizationCenter.shared.authorizationStatus == .approved
            for lock in state.replica.locks {
                guard let receipt = state.receipts.first(where: { $0.lockID == lock.id }) else { continue }
                if lock.end <= now && [.active, .partial, .pending].contains(receipt.coverage) {
                    // Only a monitor boundary provides completion evidence. A late launch cannot prove continuity.
                    state.receipt(lock, authorized && monitorEnded == lock.id && receipt.coverage == .active ? .completed : .interrupted, now: now)
                    center.stopMonitoring([DeviceActivityName(lock.id.uuidString)])
                } else if lock.isLive(at: now) && !authorized && [.active, .partial].contains(receipt.coverage) {
                    state.receipt(lock, .interrupted, now: now)
                }
            }
            if !authorized { state.selections.removeAll() }
            try apply(&state, now: now)
        }
    }
    static func start(_ lock: Lock, picks: FamilyActivitySelection, remote: Bool = false) throws {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else { throw BlockrError.unavailable("Allow Screen Time access, then pick apps on this device.") }
        guard hasSelection(picks) || !lock.group.domains.isEmpty else { throw BlockrError.emptySelection }
        let data = try JSONEncoder().encode(picks)
        // Save pending intent before scheduling: a crash must not discard an irreversible start.
        try Storage.update { state in
            if !remote { try state.replica.start(lock, at: Date()) }
            state.snapshots[lock.id.uuidString] = data
            state.receipt(lock, .pending)
        }
        do {
            try schedule(lock, now: Date())
            try Storage.update { state in
                try apply(&state, now: Date())
                state.receipt(lock, .active)
            }
        } catch {
            center.stopMonitoring([DeviceActivityName(lock.id.uuidString)])
            try Storage.update { state in
                state.receipt(lock, .failed)
                try apply(&state, now: Date())
            }
            throw error
        }
    }
}
#endif
