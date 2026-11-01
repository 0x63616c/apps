import SwiftUI
import BlockrCore
#if os(iOS)
import FamilyControls
#endif

@MainActor final class Model: ObservableObject {
    @Published var state = LocalState()
    @Published var error: String?
    @Published var syncStatus = CloudSync.Status.unavailable
    @Published var authorized = false
    @Published var loaded = false
    @Published var isStarting = false
    let sync = CloudSync()
    let fixture = ProcessInfo.processInfo.arguments.contains("--screenshots")
    private var syncTicks = 0
    var live: [Lock] { state.replica.liveLocks(at: Date()) }
    var locked: Bool { !live.isEmpty }
    var groups: [Group] { state.replica.visibleGroups }
    init() {
        if fixture {
            state.onboardingComplete = true
            authorized = true
            state.replica.groups = [Group(name: "Social", domains: ["example.com"], categoryIntent: "Social apps", revision: Revision(1, device: "fixture"))]
            loaded = true
        } else { refresh() }
    }
    func perform(_ body: () throws -> Void) {
        do { try body(); refresh() } catch { self.error = error.localizedDescription; refresh() }
    }
    func mutate(_ body: (inout LocalState) throws -> Void) throws {
        guard loaded else { throw BlockrError.unavailable("Shared storage is not ready. Retry opening Blockr.") }
        if fixture { try body(&state) } else { try Storage.update(body) }
    }
    func refresh() {
        guard !fixture else { return }
        do {
            #if os(iOS)
            try Enforcement.reconcile()
            authorized = AuthorizationCenter.shared.authorizationStatus == .approved
            #endif
            state = try Storage.read()
            loaded = true
        } catch { self.error = error.localizedDescription; loaded = false }
    }
    func tick() async {
        refresh()
        syncTicks += 1
        if syncTicks % 6 == 1 { await synchronize() }
    }
    func synchronize() async {
        guard !fixture else { return }
        syncStatus = .syncing
        syncStatus = await sync.synchronize()
        refresh()
        #if os(iOS)
        // Apply each remaining remote intent independently; union enforcement releases at each original end.
        for lock in live where !state.receipts.contains(where: { $0.lockID == lock.id }) {
            guard authorized else { continue }
            let picks = Enforcement.selection(state.selections[lock.group.id.uuidString])
            do {
                try Enforcement.start(lock, picks: picks, remote: true)
            } catch {
                try? Storage.update { $0.receipt(lock, .failed) }
                self.error = "Lock from another device: \(error.localizedDescription)"
            }
        }
        refresh()
        #endif
    }
    func authorize() async {
        #if os(iOS)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refresh()
            if authorized { perform { try mutate { $0.onboardingComplete = true } } }
            else { error = "Screen Time access was not approved. Allow access to start a lock." }
        } catch { self.error = "Screen Time: \(error.localizedDescription)" }
        #else
        perform { try mutate { $0.onboardingComplete = true } }
        #endif
    }
    func saveGroup(id: UUID?, name: String, intent: String, domains: String, selection: Data?) {
        perform {
            try mutate { state in
                try state.replica.requireEditable(at: Date())
                let name = try Validation.name(name, others: state.replica.visibleGroups.filter { $0.id != id }.map(\.name))
                let hosts = try Validation.domains(domains)
                guard intent.count <= 80 else { throw BlockrError.unavailable("Keep the category hint under 80 characters.") }
                #if os(iOS)
                let picks = Enforcement.selection(selection)
                guard Enforcement.hasSelection(picks) || !hosts.isEmpty else { throw BlockrError.emptySelection }
                guard picks.applicationTokens.count <= 50, picks.categoryTokens.count <= 50, picks.webDomainTokens.count <= 50 else { throw BlockrError.unavailable("Pick at most 50 items of each kind.") }
                #else
                guard !hosts.isEmpty || !intent.isEmpty else { throw BlockrError.emptySelection }
                #endif
                let group = Group(id: id ?? UUID(), name: name, domains: hosts, categoryIntent: intent, revision: state.replica.nextRevision(device: state.deviceID))
                state.replica.groups.removeAll { $0.id == group.id }
                state.replica.groups.append(group)
                state.selections[group.id.uuidString] = selection
            }
        }
    }
    func deleteGroup(_ group: Group) {
        perform { try mutate { state in
            try state.replica.requireEditable(at: Date())
            var tombstone = group
            tombstone.deleted = true
            tombstone.revision = state.replica.nextRevision(device: state.deviceID)
            state.replica.groups.removeAll { $0.id == group.id }
            state.replica.groups.append(tombstone)
            state.selections.removeValue(forKey: group.id.uuidString)
        } }
    }
    func saveDuration(_ seconds: Int, replacing old: Int? = nil) {
        perform { try mutate { state in
            try state.replica.requireEditable(at: Date())
            guard (900...604800).contains(seconds) else { throw BlockrError.invalidDuration }
            let revision = state.replica.nextRevision(device: state.deviceID)
            if let old, old != seconds, !Durations.presets.contains(old) {
                state.replica.durations.removeAll { $0.seconds == old }
                state.replica.durations.append(DurationPreference(seconds: old, revision: revision, deleted: true))
            }
            if !Durations.presets.contains(seconds) {
                state.replica.durations.removeAll { $0.seconds == seconds }
                state.replica.durations.append(DurationPreference(seconds: seconds, revision: revision))
            }
        } }
    }
    func deleteDuration(_ seconds: Int) {
        perform { try mutate { state in
            try state.replica.requireEditable(at: Date())
            guard !Durations.presets.contains(seconds) else { return }
            let revision = state.replica.nextRevision(device: state.deviceID)
            state.replica.durations.removeAll { $0.seconds == seconds }
            state.replica.durations.append(DurationPreference(seconds: seconds, revision: revision, deleted: true))
        } }
    }
    func start(group: Group, seconds: Int) async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        perform {
            guard !locked else { throw BlockrError.locked }
            let lock = try Lock(group: group, start: Date(), duration: seconds, origin: state.deviceID)
            #if os(iOS)
            if fixture { try state.replica.start(lock, at: Date()); state.receipt(lock, .active) }
            else { try Enforcement.start(lock, picks: Enforcement.selection(state.selections[group.id.uuidString])) }
            #else
            throw BlockrError.unavailable("Timed website blocking needs a signed content filter. This build cannot protect this Mac.")
            #endif
        }
        await synchronize()
    }
    #if os(iOS)
    func setUpLocalProtection(_ lock: Lock, picks: FamilyActivitySelection) {
        perform {
            // Local readiness may be repaired during a remote lock; group metadata remains immutable.
            let data = try JSONEncoder().encode(picks)
            try mutate { $0.selections[lock.group.id.uuidString] = data }
            try Enforcement.start(lock, picks: picks, remote: true)
        }
    }
    #endif
    var syncLabel: String {
        switch syncStatus {
        case .unavailable: "iCloud unavailable"
        case .off: "iCloud off"
        case .signedOut: "Not signed in to iCloud"
        case .syncing: "Syncing"
        case .current: "Up to date"
        case .error: "Sync error"
        }
    }
}
