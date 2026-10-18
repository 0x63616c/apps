import SwiftUI
import RDesign

struct SettingsView: View {
    @Bindable var store: LibraryStore
    @State private var backgroundScan = BackgroundScanCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Appearance", selection: $store.appearance) {
                    ForEach(Appearance.allCases, id: \.rawValue) { appearance in
                        Text(appearance.rawValue.capitalized).tag(appearance)
                    }
                }
                Section {
                    Toggle(isOn: $store.downloadFromICloud) {
                        HStack(spacing: 4) {
                            Text("Download from iCloud")
                            InfoButton("Download screenshots from iCloud Photos. Analysis stays on your iPhone.")
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(RPalette.graphite)
                }
                Section {
                    if backgroundScan.hasRequest {
                        Button("Stop background scan", systemImage: "stop.circle") {
                            Task { await backgroundScan.stop() }
                        }
                        .accessibilityIdentifier("stopBackgroundScan")
                    } else {
                        Button("Continue scan in background", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                            Task {
                                await backgroundScan.requestContinuation(
                                    completed: store.scanCompleted, total: store.scanTotal)
                            }
                        }
                        .disabled(!store.isReady || !backgroundScan.isConfigured || store.scanTotal <= store.scanCompleted)
                        .accessibilityIdentifier("continueBackgroundScan")
                    }
                    Text(backgroundScan.status).font(.subheadline).foregroundStyle(.secondary)
                } header: {
                    Text("Background scanning")
                } footer: {
                    Text("Opt in for this scan only. iOS may let text indexing continue after you leave Shotr, with progress and a cancel button in its system activity. iOS decides how long it can run; cancellation, device conditions, or force-quitting can stop it. Saved progress is kept. Automatic tags finish when Shotr is open. New screenshots are discovered when you reopen Shotr—not by an always-on background watcher.")
                }
                if let scan = store.lastScan {
                    Section("Last scan") {
                        LabeledContent("Screenshots", value: "\(scan.completed)")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Screenshots scanned")
                            .accessibilityValue("\(scan.completed)")
                            .accessibilityIdentifier("lastScanCount")
                        LabeledContent("Active time", value: ScanMeasurement.duration(scan.elapsed))
                        LabeledContent("Load images", value: ScanMeasurement.duration(scan.imageSeconds))
                        LabeledContent("Read text & images", value: ScanMeasurement.duration(scan.analysisSeconds))
                        LabeledContent("Descriptions & tags", value: scan.aiAvailable ? ScanMeasurement.duration(scan.taggingSeconds) : "Not run")
                        if scan.failed > 0 { Text("\(scan.failed) could not be fully scanned.").foregroundStyle(.secondary) }
                    }
                }
                if let message = store.aiMessage {
                    Section("Automatic tags") {
                        Text(message).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {} footer: { AppVersionFooter() }
            }
            .scrollContentBackground(.hidden).background(Color.shotrBackground)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .tint(RPalette.graphite)
    }
}
