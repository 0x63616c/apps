import SwiftUI
import BlockrCore

struct StatsView: View {
    @EnvironmentObject private var model: Model
    var stats: Statistics { Statistics(locks: model.state.replica.locks, receipts: model.state.receipts, now: Date()) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageTitle(title: "Stats")
                metric("Unbroken locks", "\(stats.streak)")
                metric("Completed locks", "\(stats.completed)")
                if model.live.isEmpty {
                    metric("Time locked", Durations.label(Int(stats.timeLocked)))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let date = model.timerDate(context.date)
                        let total = Statistics.lockedSeconds(locks: model.state.replica.locks, receipts: model.state.receipts, at: date)
                        let counting = model.state.replica.liveLocks(at: date).contains { lock in
                            model.state.receipts.contains { $0.lockID == lock.id && $0.hasInstalledCoverage && !$0.interruptionObserved && ($0.appliedAt ?? lock.start) <= date }
                        }
                        if !counting {
                            metric("Time locked", Durations.label(Int(total)))
                        } else {
                            metric("Time locked", Durations.clock(total))
                        }
                    }
                }
                metric("Shield-button taps", "\(model.state.attempts.count)")
                metric("Blocked opens", "—")
                metric("Estimated time saved", "—")
                DisclosureGroup("About these stats") {
                    Text("Shield taps are recorded on this device when you close a shield. They do not count every blocked open. Unbroken locks are locally completed sessions with no observed interruption.").foregroundStyle(.secondary)
                    Text("Time saved and per-app usage are unavailable. Blockr does not have a verified usage baseline. Time locked includes the current installed lock and counts overlapping sessions once.").foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: 640)
        }.background(.black)
    }
    private func metric(_ label: String, _ value: String) -> some View {
        metric(label, value: Text(value.isEmpty ? "0m" : value))
    }
    private func metric(_ label: String, value: Text) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label)
                Spacer(minLength: 8)
                value.font(.title2.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
            }.frame(minHeight: 44)
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}
struct SettingsView: View {
    @EnvironmentObject private var model: Model
    @State private var reset = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageTitle(title: "Settings")
                if model.locked { lockedContents }
                else {
                    Text("iCloud").font(.title2.weight(.medium))
                    Text(model.syncLabel)
                    if case .unavailable = model.syncStatus { Text("iCloud is not enabled in this build. Groups and locks stay on this device.").foregroundStyle(.secondary) }
                    if case .error(let reason) = model.syncStatus { Text(reason).foregroundStyle(.secondary) }
                    if let last = model.state.lastSync { Text("Last synced \(last.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary) }
                    Toggle("Sync with iCloud", isOn: Binding(get: { model.state.syncEnabled }, set: { enabled in model.perform { try model.mutate { state in try state.replica.requireEditable(at: Date()); state.syncEnabled = enabled } } })).disabled(model.locked || model.syncStatus == .unavailable)
                    Button("Retry sync") { Task { await model.synchronize() } }.frame(minHeight: 44)
                    DisclosureGroup("About sync") {
                        Text("App picks stay on each device. A device needs its own setup and a connection to receive a lock. Offline devices cannot start it immediately.").foregroundStyle(.secondary)
                    }
                    Divider()
                    #if os(iOS)
                    HStack { Text("Screen Time"); Spacer(); Text(model.authorized ? "Allowed" : "Needs access").foregroundStyle(.secondary) }
                    if !model.authorized { Button("Allow Screen Time") { Task { await model.authorize() } } }
                    #else
                    MacFilterSetupView(filter: model.filter)
                    Text("Manual Screen Time website restrictions are separate from Blockr locks and do not expire with them.").foregroundStyle(.secondary)
                    #endif
                    Divider()
                    Text("Data").font(.title2.weight(.medium))
                    Button("Reset this device") { reset = true }.disabled(model.locked)
                    Divider()
                    Text("Blockr").font(.title2.weight(.medium))
                    Link("Privacy policy", destination: URL(string: "https://0x63616c.github.io/apps/blockr/privacy/")!).frame(minHeight: 44)
                    Link("Support", destination: URL(string: "https://0x63616c.github.io/apps/blockr/support/")!).frame(minHeight: 44)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")").foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: 640)
        }.background(.black)
        .confirmationDialog("Reset this device?", isPresented: $reset) {
            Button("Reset local data") {
                model.perform { try model.mutate { state in
                    try state.replica.requireEditable(at: Date())
                    let device = state.deviceID, account = state.accountID, linked = state.accountHasBeenLinked
                    state = LocalState(); state.deviceID = device; state.accountID = account; state.accountHasBeenLinked = linked; state.onboardingComplete = true
                } }
            }
            Button("Keep data", role: .cancel) {}
        } message: { Text("Removes local groups, picks and stats. Synced groups may return. No iCloud records are deleted.") }
    }
    @ViewBuilder private var lockedContents: some View {
        Label("Settings are locked until your lock ends.", systemImage: "lock").foregroundStyle(.secondary)
        if let lock = model.live.last {
            Text("Until \(lock.end.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
        }
        #if os(iOS)
        HStack { Text("Screen Time"); Spacer(); Text(model.authorized ? "Allowed" : "Needs access").foregroundStyle(.secondary) }.frame(minHeight: 44)
        if !model.authorized { Button("Allow Screen Time") { Task { await model.authorize() } } }
        #else
        HStack { Text("Website protection"); Spacer(); Text(model.filter.label).foregroundStyle(.secondary) }.frame(minHeight: 44)
        if model.filter.configured && model.filter.status != .enabled { MacFilterSetupView(filter: model.filter) }
        #endif
        Divider()
        HStack { Text("Manage groups"); Spacer(); Label("Locked", systemImage: "lock").foregroundStyle(.secondary) }.frame(minHeight: 44)
        Divider()
        HStack {
            Button("Reset this device") {}.disabled(true)
            Spacer()
            Label("Locked", systemImage: "lock").foregroundStyle(.secondary)
        }.frame(minHeight: 44)
        Divider()
        HStack { Text("iCloud"); Spacer(); Text(model.syncLabel).foregroundStyle(.secondary) }.frame(minHeight: 44)
        if case .error(let reason) = model.syncStatus { Text(reason).foregroundStyle(.secondary) }
        DisclosureGroup("About Blockr") {
            Link("Privacy policy", destination: URL(string: "https://0x63616c.github.io/apps/blockr/privacy/")!).frame(minHeight: 44)
            Link("Support", destination: URL(string: "https://0x63616c.github.io/apps/blockr/support/")!).frame(minHeight: 44)
        }
    }
}
