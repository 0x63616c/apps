import SwiftUI
import BlockrCore
#if os(iOS)
import FamilyControls
#endif

enum Page: String, CaseIterable, Identifiable {
    case lock = "Lock", groups = "Groups", stats = "Stats", settings = "Settings"
    var id: String { rawValue }
    var symbol: String { switch self { case .lock: "lock"; case .groups: "square.stack"; case .stats: "chart.bar"; case .settings: "gearshape" } }
}
struct RootView: View {
    @EnvironmentObject private var model: Model
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: Page? = .lock
    var body: some View {
        SwiftUI.Group {
            if !model.loaded {
                ContentUnavailableView { Label("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark") } description: { Text("Blockr could not read its shared data.") } actions: { Button("Retry") { model.refresh() } }
            } else if !model.state.onboardingComplete {
                WelcomeView()
            } else {
                #if os(macOS)
                NavigationSplitView {
                    List(Page.allCases, selection: $page) { item in Label(item.rawValue, systemImage: item.symbol).tag(item) }
                        .navigationTitle("Blockr").navigationSplitViewColumnWidth(224)
                } detail: { destination(page ?? .lock).padding(32).frame(minWidth: 520, minHeight: 550) }
                #else
                TabView {
                    ForEach([Page.lock, .stats, .settings]) { item in
                        NavigationStack { destination(item) }.tabItem { Label(item.rawValue, systemImage: item.symbol) }
                    }
                }
                #endif
            }
        }
        .background(Color.black)
        .alert("Blockr", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task { await model.synchronize() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.synchronize() } } }
        .onReceive(NotificationCenter.default.publisher(for: .init("BlockrShowLock"))) { _ in page = .lock }
    }
    @ViewBuilder private func destination(_ page: Page) -> some View {
        switch page { case .lock:
            #if os(iOS)
            HomeLockView()
            #else
            LockView()
            #endif
        case .groups: GroupsView(); case .stats: StatsView(); case .settings: SettingsView() }
    }
}
struct WelcomeView: View {
    @EnvironmentObject private var model: Model
    @State private var requesting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 76, weight: .ultraLight)).accessibilityHidden(true)
            Text("Make room.\nStay with it.").font(.system(size: 42, weight: .semibold)).tracking(-1.5)
            #if os(iOS)
            Text("Pick what to block. Set a time. Let it pass.").foregroundStyle(.secondary)
            Text("Blockr needs Screen Time access to shield your apps and websites. Your choices stay on this device.").foregroundStyle(.secondary)
            primary(requesting ? "Requesting access…" : "Allow Screen Time") {
                requesting = true
                Task { await model.authorize(); requesting = false }
            }.disabled(requesting)
            Button("Open Settings") { openSettings() }
            #else
            Text("Groups and lock schedules, together on your Mac.").foregroundStyle(.secondary)
            Text("App blocking is unavailable on macOS. Website locks need a signed content filter and your approval in Settings.").foregroundStyle(.secondary)
            primary("Continue") { Task { await model.authorize() } }
            #endif
            Spacer()
            Text("Blockr").font(.headline)
        }.padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity).background(.black)
    }
}
func openSettings() {
    #if os(iOS)
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    #else
    if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") { NSWorkspace.shared.open(url) }
    #endif
}
func primary(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(minHeight: 54).contentShape(Rectangle()) }
        .buttonStyle(.plain).background(.white, in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(.black)
}
struct PageTitle: View {
    var title: String
    var body: some View { Text(title).font(.largeTitle.weight(.semibold)).tracking(-1).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader).accessibilityIdentifier("pageHeader-\(title)") }
}

struct HomeLockView: View {
    @EnvironmentObject private var model: Model
    @State private var start = false
    @State private var editor = false
    @State private var editing: BlockrCore.Group?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(model.locked ? "Locked." : "Take your time back.")
                    .font(.largeTitle.weight(.semibold)).tracking(-1)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("pageHeader-Blockr")
                if model.locked { ActiveView() }
                else {
                    if model.groups.isEmpty { Text("Create a group of apps and websites.").foregroundStyle(.secondary) }
                    ForEach(model.groups) { group in
                        Button { editing = group; editor = true } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "lock").font(.title2)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.name).font(.title3.weight(.medium))
                                    Text(group.categoryIntent.isEmpty ? "\(group.domains.count) websites" : group.categoryIntent).foregroundStyle(.secondary)
                                    #if os(iOS)
                                    if group.requiresLocalSelection && model.state.selections[group.id.uuidString] == nil {
                                        Text("Pick apps on this device").font(.callout).foregroundStyle(.secondary)
                                    }
                                    #endif
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.frame(minHeight: 64).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu { Button("Delete group", role: .destructive) { model.deleteGroup(group) } }
                        Divider()
                    }
                    Button { editing = nil; editor = true } label: {
                        HStack(spacing: 16) { Image(systemName: "plus").font(.title2); Text("New group").font(.title3); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.frame(minHeight: 54).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider()
                }
            }.padding(24).frame(maxWidth: 600)
        }.background(.black)
        .safeAreaInset(edge: .bottom) {
            if !model.locked {
                primary("Start a lock") { start = true }.disabled(model.groups.isEmpty).padding(24).background(.black)
            }
        }
        .sheet(isPresented: $editor) { GroupEditor(group: editing) }
        .navigationDestination(isPresented: $start) { LockView() }
    }
}

struct LockView: View {
    @EnvironmentObject private var model: Model
    @State private var selectedGroup: UUID?
    @State private var duration = Durations.defaultValue
    private enum Modal: String, Identifiable { case custom, confirmation; var id: String { rawValue } }
    @State private var modal: Modal?
    @State private var editingDuration: Int?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageTitle(title: model.locked ? "Locked." : "Start a lock")
                if model.locked { ActiveView() }
                else {
                    Image(systemName: "lock.shield").font(.system(size: 56, weight: .ultraLight)).frame(maxWidth: .infinity).padding(.vertical, 16).accessibilityHidden(true)
                    Text("A little space.").font(.title.weight(.medium))
                    if model.groups.isEmpty {
                        Text("Create a group in Groups to get started.").foregroundStyle(.secondary)
                    } else {
                        Picker("Group", selection: $selectedGroup) {
                            Text("Choose a group").tag(Optional<UUID>.none)
                            ForEach(model.groups) { Text($0.name).tag(Optional($0.id)) }
                        }.pickerStyle(.menu).frame(minHeight: 44)
                        Text("For how long?").font(.title3.weight(.medium))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78))], spacing: 12) {
                            ForEach(Durations.sorted(custom: model.state.replica.customDurations), id: \.self) { seconds in
                                Button { duration = seconds } label: {
                                    Text(Durations.label(seconds)).font(.body.weight(.medium)).frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .background(duration == seconds ? Color.white : Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(duration == seconds ? .black : .white)
                                    .accessibilityLabel(Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide)))
                                    .accessibilityAddTraits(duration == seconds ? .isSelected : [])
                                    .contextMenu {
                                        if !Durations.presets.contains(seconds) {
                                            Button("Edit saved duration") { editingDuration = seconds; modal = .custom }
                                            Button("Delete duration", role: .destructive) { model.deleteDuration(seconds); if duration == seconds { duration = 7200 } }
                                        }
                                    }
                            }
                            Button { editingDuration = nil; modal = .custom } label: { Image(systemName: "plus").frame(maxWidth: .infinity).frame(height: 48) }.buttonStyle(.bordered).accessibilityLabel("Add custom duration")
                        }
                        if !model.state.replica.customDurations.isEmpty {
                            Menu("Edit saved duration") {
                                ForEach(model.state.replica.customDurations.sorted(), id: \.self) { seconds in
                                    Button(Durations.label(seconds)) { editingDuration = seconds; modal = .custom }
                                }
                            }.frame(minHeight: 44)
                        }
                        #if os(iOS)
                        if !model.authorized {
                            Text("Screen Time access is needed.").foregroundStyle(.secondary)
                            Button("Allow Screen Time") { Task { await model.authorize() } }
                        }
                        #else
                        MacFilterSetupView(filter: model.filter)
                        #endif
                        primary("Review lock") { modal = .confirmation }.disabled(selectedGroup == nil || model.isStarting)
                    }
                }
            }.padding(24).frame(maxWidth: 600)
        }.background(.black)
        .onAppear { if selectedGroup == nil { selectedGroup = model.groups.first?.id } }
        .sheet(item: $modal) { presented in
            if presented == .custom { DurationEditor(selected: $duration, original: editingDuration) }
            else if let group = model.groups.first(where: { $0.id == selectedGroup }) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Ready to lock?").font(.largeTitle.weight(.semibold))
                    Text(group.name).font(.title2)
                    Text(group.categoryIntent.isEmpty ? "Your selections on this device" : group.categoryIntent).foregroundStyle(.secondary)
                    Text(Durations.label(duration)).font(.system(size: 56, weight: .medium)).monospacedDigit()
                    Text("Until \(Date().addingTimeInterval(Double(duration)).formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                    Text("No cancelling once started.")
                    primary(model.isStarting ? "Starting…" : "Start lock") {
                        Task {
                            await model.start(group: group, seconds: duration)
                            modal = nil
                            #if os(iOS)
                            if model.locked { dismiss() }
                            #endif
                        }
                    }.disabled(model.isStarting || model.locked)
                    Button("Keep choosing") { modal = nil }.frame(maxWidth: .infinity, minHeight: 44).disabled(model.isStarting)
                }.padding(32).frame(minWidth: 300).presentationDetents([.large]).interactiveDismissDisabled(model.isStarting)
            }
        }
    }
}
struct ActiveView: View {
    @EnvironmentObject private var model: Model
    #if os(iOS)
    @State private var choosing = false
    @State private var picks = FamilyActivitySelection()
    @State private var pickingLock: Lock?
    #endif
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 64.0
    var body: some View {
        if let lock = model.live.last {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "lock.fill").font(.largeTitle).accessibilityHidden(true)
                Text(lock.group.name).font(.title2.weight(.medium))
                Text(lock.end, style: .timer).font(.system(size: timerSize, weight: .medium)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1).accessibilityLabel("Lock ends \(lock.end.formatted())")
                if lock.origin != model.state.deviceID { Text("Started on another device").foregroundStyle(.secondary) }
                Text("Until \(lock.end.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                ForEach(model.live) { item in
                    let coverage = model.state.receipts.first { $0.lockID == item.id }?.coverage ?? .pending
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(item.group.name); Spacer(); Text(coverage == .active ? "Locked" : coverage == .partial ? "Partly protected" : "Not protected here").foregroundStyle(.secondary) }
                        #if os(iOS)
                        if coverage != .active && model.authorized {
                            Button("Pick apps for \(item.group.name)") {
                                pickingLock = item
                                picks = Enforcement.selection(model.state.selections[item.group.id.uuidString])
                                choosing = true
                            }
                        }
                        #endif
                    }
                }
                if model.live.contains(where: { item in !model.state.receipts.contains { $0.lockID == item.id && $0.coverage == .active } }) {
                    Text("This device needs local setup. Locks on your other devices keep running.").foregroundStyle(.secondary)
                    #if os(iOS)
                    if !model.authorized {
                        Button("Allow Screen Time") { Task { await model.authorize() } }
                    }
                    #endif
                }
                Text("Let the time pass.").font(.title3).padding(.top, 32)
                DisclosureGroup("View group") {
                    if !lock.group.categoryIntent.isEmpty { Text(lock.group.categoryIntent) }
                    ForEach(lock.group.domains, id: \.self) { Text($0) }
                    #if os(iOS)
                    let selection = Enforcement.selection(model.state.snapshots[lock.id.uuidString])
                    Text("\(selection.applicationTokens.count) apps · \(selection.categoryTokens.count) categories · \(selection.webDomainTokens.count) websites").foregroundStyle(.secondary)
                    #endif
                }
            }.padding(.vertical, 32)
            #if os(iOS)
            .familyActivityPicker(isPresented: $choosing, selection: $picks)
            .onChange(of: choosing) { old, new in
                if old && !new && Enforcement.hasSelection(picks) {
                    if let pickingLock, pickingLock.isLive(at: Date()) {
                        model.setUpLocalProtection(pickingLock, picks: picks)
                    }
                }
            }
            #endif
        }
    }
}
struct DurationEditor: View {
    @EnvironmentObject private var model: Model
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Int
    var original: Int?
    @State private var days = ""
    @State private var hours = ""
    @State private var minutes = ""
    @State private var validation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(original == nil ? "Custom duration" : "Edit duration").font(.title.weight(.semibold))
            HStack {
                field("Days", text: $days); field("Hours", text: $hours); field("Minutes", text: $minutes)
            }
            Text("15 minutes to 7 days").foregroundStyle(.secondary)
            if let validation { Text(validation) }
            primary("Save duration") {
                do {
                    let value = try Durations.parse(days: days, hours: hours, minutes: minutes)
                    model.error = nil
                    model.saveDuration(value, replacing: original)
                    if model.error == nil { selected = value; dismiss() }
                } catch { validation = error.localizedDescription }
            }.disabled(model.locked)
            if let original {
                Button("Delete duration", role: .destructive) { model.deleteDuration(original); if selected == original { selected = 7200 }; dismiss() }.disabled(model.locked)
            }
            Button("Cancel") { dismiss() }.accessibilityIdentifier("duration-cancel")
        }.padding(32).frame(minWidth: 300).presentationDetents([.medium, .large])
        .onAppear { if let original { days = String(original / 86400); hours = String(original % 86400 / 3600); minutes = String(original % 3600 / 60) } }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) { Text(title).foregroundStyle(.secondary); TextField("0", text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title) }
    }
}
