import SwiftUI

private enum HistoryEntry: Identifiable {
    case weight(WeightEntry), dose(DoseEntry)
    var id: UUID { switch self { case .weight(let e): e.id; case .dose(let e): e.id } }
    var date: Date { switch self { case .weight(let e): e.date; case .dose(let e): e.date } }
    var kind: String { switch self { case .weight: "Weight"; case .dose: "Doses" } }
}

struct JournalView: View {
    @Environment(Store.self) private var store
    @State private var weight: WeightEntry?
    @State private var dose: DoseEntry?
    @State private var deleting: HistoryEntry?
    @State private var adding: String?
    @Binding var filter: String
    private var entries: [HistoryEntry] {
        (store.journal.weights.map(HistoryEntry.weight) + store.journal.doses.map(HistoryEntry.dose))
            .filter { filter == "All" || $0.kind == filter }.sorted { $0.date > $1.date }
    }
    private var days: [Date] { Array(Set(entries.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                PageHeader("Journal") {
                    Menu { Button("Weight") { adding = "Weight" }; Button("Dose") { adding = "Dose" } } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }.frame(width: 44, height: 44).accessibilityLabel("Add entry")
                }.padding(.horizontal, 24)
                List {
                    Section {
                        FilterBar(selection: $filter, options: ["All", "Doses", "Weight"].map { ($0, $0) })
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    ForEach(days, id: \.self) { day in
                        Section(day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { entry in
                                Button { edit(entry) } label: { row(entry) }.buttonStyle(.plain)
                                    .disabled(entry.isHealthKitWeight)
                                    .swipeActions(allowsFullSwipe: false) {
                                        if !entry.isHealthKitWeight { Button("Delete", role: .destructive) { deleting = entry }.tint(.red) }
                                    }
                                }
                            }
                    }
                    if entries.isEmpty { ContentUnavailableView("No entries yet", systemImage: "book.closed", description: Text("Your doses and weights appear here.")) }
                }
                .scrollContentBackground(.hidden)
            }.background(Theme.background).toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
                    if adding == "Weight" { WeightEditor() } else { DoseEditor() }
                }
                .sheet(item: $weight) { WeightEditor(entry: $0) }
                .sheet(item: $dose) { DoseEditor(entry: $0) }
                .alert("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete entry", role: .destructive) {
                        guard let deleting else { return }
                        switch deleting {
                        case .weight(let e): store.delete(weight: e)
                        case .dose(let e): store.delete(dose: e)
                        }
                        self.deleting = nil
                    }
                }
        }
    }
    private func edit(_ entry: HistoryEntry) {
        switch entry { case .weight(let e): weight = e; case .dose(let e): dose = e }
    }
    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 14) {
            switch entry {
            case .dose(let e):
                Image(systemName: e.status == .taken ? "checkmark.circle.fill" : e.status == .skipped ? "minus.circle" : "circle.dashed").foregroundStyle(e.status == .taken ? Theme.pine : Color.secondary).font(.title2)
                details(title: e.status == .skipped ? "Skipped · \(e.medication)" : "\(number(e.milligrams, digits: 3)) mg · \(e.medication)", subtitle: e.status.rawValue.capitalized, note: e.note)
            case .weight(let e):
                Image(systemName: "scalemass.fill").foregroundStyle(Theme.weight).font(.title2)
                details(title: "\(number(store.journal.unit.display(e.kilograms))) \(store.journal.unit.symbol)", subtitle: e.healthKitID == nil ? (e.date > Date() ? "Planned weight" : "Weight") : "Apple Health · \(e.sourceName ?? "Imported")", note: e.note)
            }
            Spacer(minLength: 4)
            Text(entry.date, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
    private func details(title: String, subtitle: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            if !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3).accessibilityIdentifier("journalNote")
            }
        }
    }
}
private extension HistoryEntry {
    var isHealthKitWeight: Bool {
        if case .weight(let entry) = self { return entry.healthKitID != nil }
        return false
    }
}
struct SettingsView: View {
    @Environment(Store.self) private var store
    @State private var schedule = false
    @State private var treatment = false
    @State private var addingVial = false
    @State private var editingVial: Vial?
    @State private var tipJar = TipJar.shared
    @State private var tipping = false
    @State private var thanks: TipJar.Tip?
    var body: some View {
        @Bindable var accents = Theme.preferences
        NavigationStack {
            VStack(spacing: 8) {
                PageHeader("Settings").padding(.horizontal, 24)
                Form {
                    Section("Preferences") {
                        Picker("Accent", selection: $accents.selection) {
                            ForEach(accents.options, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Weight unit", selection: Binding(get: { store.journal.unit }, set: { var next = store.journal; next.unit = $0; _ = store.commit(next) })) { ForEach(WeightUnit.allCases, id: \.self) { Text($0.symbol).tag($0) } }
                        Picker("Weight trend", selection: Binding(get: { store.journal.weightTrend }, set: { var next = store.journal; next.weightTrend = $0; _ = store.commit(next) })) {
                            ForEach(WeightTrendMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("weightTrendPicker")
                        if FeatureFlags.syringeUnits { Button("Dose entry") { treatment = true } }
                        Picker("Appearance", selection: Binding(get: { store.journal.appearance }, set: { var next = store.journal; next.appearance = $0; _ = store.commit(next) })) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    }
                    Section {
                        HStack {
                            Button {
                                Task { await store.connectHealthKit() }
                            } label: {
                                HStack {
                                    Label(store.journal.healthKitWeightsEnabled ? "Sync body weight" : "Connect Apple Health", systemImage: "heart.fill")
                                    Spacer()
                                    if store.journal.healthKitWeightsEnabled { Image(systemName: "arrow.clockwise").foregroundStyle(.secondary) }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.borderless)
                            InfoButton(store.journal.healthKitWeightsEnabled
                                       ? "Tendr checks Apple Health for new weights each time you open it. Tap Sync body weight to check now. Read-only: Tendr never writes to Apple Health."
                                       : "Read-only. Tendr reads your body weight and never writes to Apple Health.")
                                .accessibilityIdentifier("appleHealthInfo")
                        }
                        if store.journal.healthKitWeightsEnabled {
                            LabeledContent("Status", value: store.healthKitStatus)
                            LabeledContent("Last synced") {
                                if let synced = store.journal.lastHealthKitSync {
                                    Text(synced, format: .relative(presentation: .named)) + Text(" · ") + Text(synced, format: .dateTime.hour().minute())
                                } else {
                                    Text("Not yet")
                                }
                            }.accessibilityIdentifier("lastHealthSync")
                        }
                    } header: { Text("Apple Health") }
                    Section {
                        HStack(spacing: 2) {
                            Text("Start weights at first dose")
                            InfoButton(store.firstDoseDate == nil
                                       ? "Log your first dose to use this option."
                                       : "Removes weights from before your first dose and filters them from future Apple Health syncs. Apple Health is unchanged.")
                                .accessibilityIdentifier("firstDoseWeightsInfo")
                            Spacer(minLength: 8)
                            // Only the switch is disabled, so the explanation stays reachable.
                            Toggle("Start weights at first dose", isOn: Binding(
                                get: { store.journal.weightsStartAtFirstDose },
                                set: { _ = store.setWeightsStartAtFirstDose($0) }
                            )).labelsHidden().disabled(store.firstDoseDate == nil)
                        }
                        if let firstDoseDate = store.firstDoseDate {
                            LabeledContent("First dose") { Text(firstDoseDate, format: .dateTime.month(.abbreviated).day().year()) }
                        }
                    } header: { Text("Weight history") }
                    if tipJar.phase == .ready {
                        Section {
                            Button { tipping = true } label: { Label("Support Tendr", systemImage: "heart") }
                                .accessibilityIdentifier("supportTendr")
                        }
                    }
                    Section {
                        NavigationLink { PrivacyView() } label: { Label("Privacy & About", systemImage: "lock.shield") }
                    } footer: { Text("Tendr · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").frame(maxWidth: .infinity).padding(.top, 12) }
                }.scrollContentBackground(.hidden)
            }.background(Theme.background).toolbar(.hidden, for: .navigationBar)
                .task {
                    await tipJar.load()
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("--uitest"), arguments.contains("--tip-thanks") { thanks = .medium }
                }
                .sheet(isPresented: $tipping, onDismiss: {
                    thanks = tipJar.completed
                    tipJar.completed = nil
                }) { TipJarSheet(jar: tipJar) }
                .fullScreenCover(item: $thanks) { TipThanks(tip: $0) }
                .sheet(isPresented: $schedule) { ScheduleEditor() }
                .sheet(isPresented: $treatment) { DosePreferencesEditor() }
                .sheet(isPresented: $addingVial) { VialEditor() }
                .sheet(item: $editingVial) { VialEditor(vial: $0) }
        }
    }
}
struct TreatmentEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var medication = ""
    @State private var halfLife = 7.0
    @State private var model = MedicationModel.halfLife
    @State private var u100 = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Medication name", text: $medication)
                    HStack { Button("Semaglutide") { medication = "Semaglutide"; halfLife = 7; model = .semaglutide }; Spacer(); Button("Tirzepatide") { medication = "Tirzepatide"; halfLife = 5; model = .tirzepatide } }.font(.caption)
                }
                Section("Estimate model") { Picker("Model", selection: $model) { ForEach(MedicationModel.allCases, id: \.self) { Text($0.title).tag($0) } } }
                if model == .halfLife { Section { Stepper("\(number(halfLife)) days", value: $halfLife, in: 0.5...30, step: 0.5) } header: { Text("Model half-life") } footer: { Text("Used only for the estimate graph. Your dose and schedule are set separately.") } }
                if FeatureFlags.syringeUnits { Section { Toggle("I use a U-100 syringe", isOn: $u100) } header: { Text("Dose entry") } footer: { Text("U-100 means 100 units per mL. Check the marking on your syringe.") } }
            }.navigationTitle("Treatment").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { var next = store.journal; next.medication = medication.trimmingCharacters(in: .whitespacesAndNewlines); next.halfLifeDays = halfLife; next.medicationModel = model; if FeatureFlags.syringeUnits { next.syringeUnitsPerML = u100 ? 100 : nil }; if store.commit(next) { dismiss() } }.disabled(medication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
                .onAppear { medication = store.journal.medication; halfLife = store.journal.halfLifeDays; model = store.journal.resolvedMedicationModel; u100 = store.journal.syringeUnitsPerML == 100 }
        }
    }
}
struct PrivacyView: View {
    var body: some View {
        List {
            Section("On this iPhone") { Text("No account, ads, analytics SDKs, or server. Your journal is stored locally. Device backups follow your iPhone settings.") }
            Section("Your health") { Text("Tendr is a journal, not a dosing guide. Medication graphs are simplified estimates, not measured levels. Follow your prescriber's instructions.") }
            Section("Help") {
                Link(destination: URL(string: "https://0x63616c.github.io/tendr/privacy/")!) { Label("Privacy policy", systemImage: "hand.raised") }
                Link(destination: URL(string: "https://0x63616c.github.io/tendr/support/")!) { Label("Support", systemImage: "questionmark.circle") }
            }
            if FeatureFlags.assistantPreview { Section("Assistant") { Text("The assistant is a coming-soon preview. No chat service is connected and no journal data is sent to AI.") } }
        }.navigationTitle("Privacy & About").navigationBarTitleDisplayMode(.inline)
    }
}

/// A small (i) that shows a row's explanation in a popover, instead of footer text under it.
struct InfoButton: View {
    let message: String
    @State private var showing = false
    init(_ message: String) { self.message = message }
    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle").font(.body).foregroundStyle(.secondary).frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More information")
        .popover(isPresented: $showing, arrowEdge: .top) {
            Text(message).font(.footnote).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(16)
                .presentationCompactAdaptation(.popover)
                .accessibilityIdentifier("infoPopover")
        }
    }
}
