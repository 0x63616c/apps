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
    static func schedule(_ lock: Lock, now: Date, remote: Bool) throws {
        if remote && lock.remaining(at: now) < 900 { throw BlockrError.unavailable("Less than 15 minutes remain. This device cannot install that lock.") }
        let interval = try Scheduling.components(start: remote ? now : lock.start, end: lock.end)
        let schedule = DeviceActivitySchedule(intervalStart: interval.start, intervalEnd: interval.end, repeats: false)
        try center.startMonitoring(DeviceActivityName(lock.id.uuidString), during: schedule)
    }
    static func apply(_ state: inout LocalState, now: Date) throws {
        let live = state.replica.liveLocks(at: now).filter { lock in
            state.snapshots[lock.id.uuidString] != nil && state.receipts.contains {
                $0.lockID == lock.id && $0.hasInstalledCoverage && ($0.coverage != .pending || center.activities.contains(DeviceActivityName(lock.id.uuidString)))
            }
        }
        if live.isEmpty {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = nil
            if state.removalWasCaptured {
                store.application.denyAppRemoval = state.previousDenyRemoval
                state.previousDenyRemoval = nil; state.removalWasCaptured = false
            }
            return
        }
        if !state.removalWasCaptured {
            state.previousDenyRemoval = store.application.denyAppRemoval
            state.removalWasCaptured = true
        }
        var apps = Set<ApplicationToken>(), categories = Set<ActivityCategoryToken>(), websites = Set<WebDomainToken>(), domains = Set<WebDomain>()
        for lock in live {
            let picks = selection(state.snapshots[lock.id.uuidString])
            apps.formUnion(picks.applicationTokens)
            categories.formUnion(picks.categoryTokens)
            websites.formUnion(picks.webDomainTokens)
            domains.formUnion(lock.group.domains.map { WebDomain(domain: $0) })
        }
        // Only ask for our own known identity; never resolve or inspect private selected identities.
        let ownTokens: Set<ApplicationToken> = ManagedSettings.Application(bundleIdentifier: "com.calumwebb.blockr").token.map { Set([$0]) } ?? []
        apps.subtract(ownTokens)
        guard apps.count <= 50, categories.count <= 50, websites.count <= 50, domains.count <= 50 else { throw BlockrError.unavailable("This combined lock exceeds the system’s 50-item limit.") }
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories, except: ownTokens)
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
                if lock.isLive(at: now) && receipt.installationNeedsRecovery(at: now) {
                    if center.activities.contains(DeviceActivityName(lock.id.uuidString)), state.snapshots[lock.id.uuidString] != nil, authorized {
                        // A recovered start cannot prove continuity across its missing completion.
                        let picks = selection(state.snapshots[lock.id.uuidString])
                        state.receipt(lock, .interrupted, now: now)
                        state.receipt(lock, lock.group.requiresLocalSelection && !hasSelection(picks) ? .partial : .active, now: now)
                    } else { state.receipt(lock, .failed, now: now) }
                } else if lock.end <= now && [.active, .partial, .pending].contains(receipt.coverage) {
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
        let installationID = UUID()
        var previousSnapshot: Data?
        var previousReceipt: Receipt?
        let alreadyScheduled = center.activities.contains(DeviceActivityName(lock.id.uuidString))
        // Save pending intent before scheduling: a crash must not discard an irreversible start.
        try Storage.update { state in
            if !remote { try state.replica.start(lock, at: Date()) }
            else {
                guard state.replica.locks.contains(lock), lock.isLive(at: Date()) else { throw BlockrError.locked }
            }
            previousSnapshot = state.snapshots[lock.id.uuidString]
            previousReceipt = state.receipts.first { $0.lockID == lock.id }
            let pending = try Receipt.beginInstallation(lockID: lock.id, previous: previousReceipt, id: installationID, at: Date())
            // Repair may add protection, but cannot remove an immutable session's original picks.
            var combined = selection(state.snapshots[lock.id.uuidString])
            combined.applicationTokens.formUnion(picks.applicationTokens)
            combined.categoryTokens.formUnion(picks.categoryTokens)
            combined.webDomainTokens.formUnion(picks.webDomainTokens)
            state.snapshots[lock.id.uuidString] = try JSONEncoder().encode(combined)
            state.receipts.removeAll { $0.lockID == lock.id }
            state.receipts.append(pending)
        }
        do {
            if !alreadyScheduled { try schedule(lock, now: Date(), remote: remote) }
            try Storage.update { state in
                guard state.receipts.first(where: { $0.lockID == lock.id })?.installationID == installationID else { throw BlockrError.locked }
                // Reconciliation may have observed startup; restore coverage before computing the union.
                state.receipt(lock, lock.group.requiresLocalSelection && !hasSelection(picks) ? .partial : .active)
                try apply(&state, now: Date())
            }
        } catch {
            try Storage.update { state in
                // A superseded attempt must never stop the replacement's monitor or clear its policy.
                guard state.receipts.first(where: { $0.lockID == lock.id })?.installationID == installationID else { return }
                if !alreadyScheduled { center.stopMonitoring([DeviceActivityName(lock.id.uuidString)]) }
                if let previousReceipt, [.active, .partial].contains(previousReceipt.coverage) {
                    state.snapshots[lock.id.uuidString] = previousSnapshot
                    state.receipts.removeAll { $0.lockID == lock.id }
                    state.receipts.append(previousReceipt)
                } else { state.receipt(lock, .failed) }
                try apply(&state, now: Date())
            }
            throw error
        }
    }
}
#endif
