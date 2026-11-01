import SwiftUI
import BlockrCore
#if os(iOS)
import FamilyControls
#endif

struct GroupsView: View {
    @EnvironmentObject private var model: Model
    @State private var editor = false
    @State private var editing: BlockrCore.Group?
    @State private var deleting: BlockrCore.Group?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageTitle(title: "Groups")
                if model.locked { Label("Groups are locked until your lock ends.", systemImage: "lock").foregroundStyle(.secondary) }
                if model.groups.isEmpty { Text("Keep distractions together.").font(.title2); Text("Create a group of apps and websites.").foregroundStyle(.secondary) }
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button { editing = group; editor = true } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.name).font(.title3.weight(.medium))
                                    Text(group.categoryIntent.isEmpty ? "\(group.domains.count) websites" : group.categoryIntent).foregroundStyle(.secondary)
                                    #if os(iOS)
                                    if group.requiresLocalSelection && model.state.selections[group.id.uuidString] == nil { Text("Pick apps on this device").font(.callout).foregroundStyle(.secondary) }
                                    #else
                                    Text("App blocking unavailable on Mac").font(.callout).foregroundStyle(.secondary)
                                    #endif
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.locked)
                            Button { deleting = group } label: { Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Delete \(group.name)").disabled(model.locked)
                        }
                        Divider()
                    }.padding(.vertical, 8)
                }
                primary("New group") { editing = nil; editor = true }.disabled(model.locked)
            }.padding(24).frame(maxWidth: 640)
        }.background(.black)
        .sheet(isPresented: $editor) { GroupEditor(group: editing) }
        .confirmationDialog("Delete \(deleting?.name ?? "group")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete group") { if let deleting { model.deleteGroup(deleting) }; deleting = nil }
            Button("Keep group", role: .cancel) { deleting = nil }
        } message: { Text("Your completed lock history stays.") }
    }
}
struct GroupEditor: View {
    @EnvironmentObject private var model: Model
    @Environment(\.dismiss) private var dismiss
    var group: BlockrCore.Group?
    @State private var name = ""
    @State private var intent = ""
    @State private var domains = ""
    @State private var picker = false
    @State private var discard = false
    @State private var deleting = false
    #if os(iOS)
    @State private var selection = FamilyActivitySelection()
    #endif
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Group name", text: $name).accessibilityIdentifier("group-name") }
                Section("Apps and categories") {
                    #if os(iOS)
                    Button("Pick apps on this device") { picker = true }.disabled(!model.authorized)
                    Text("\(selection.applicationTokens.count) apps · \(selection.categoryTokens.count) categories · \(selection.webDomainTokens.count) websites").foregroundStyle(.secondary)
                    if !model.authorized { Button("Allow Screen Time") { Task { await model.authorize() } } }
                    #else
                    Text("App selection is available on iPhone. App picks stay on each device.").foregroundStyle(.secondary)
                    #endif
                    TextField("Category hint (optional)", text: $intent)
                }
                Section { TextField("example.com", text: $domains, axis: .vertical).lineLimit(3...8).autocorrectionDisabled() }
                    header: { Text("Websites") }
                if let error = model.error { Section { Text(error).accessibilityLabel("Could not save: \(error)") } }
                if model.locked { Text("A lock started. Changes are unavailable until it ends.") }
                if group != nil { Section { Button("Delete group") { deleting = true }.disabled(model.locked) } }
            }
            .scrollContentBackground(.hidden).background(.black)
            .navigationTitle(group == nil ? "New group" : "Edit group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    model.error = nil
                    #if os(iOS)
                    let data = try? JSONEncoder().encode(selection)
                    #else
                    let data: Data? = nil
                    #endif
                    model.saveGroup(id: group?.id, name: name, intent: intent, domains: domains, selection: data)
                    if model.error == nil { dismiss() }
                }.disabled(model.locked) }
            }
            .confirmationDialog("Discard changes?", isPresented: $discard) { Button("Discard") { dismiss() }; Button("Keep editing", role: .cancel) {} }
            .confirmationDialog("Delete this group?", isPresented: $deleting) {
                Button("Delete group") { if let group { model.deleteGroup(group); if model.error == nil { dismiss() } } }
                Button("Keep group", role: .cancel) {}
            }
            #if os(iOS)
            .familyActivityPicker(isPresented: $picker, selection: $selection)
            #endif
        }.frame(minWidth: 320, minHeight: 480)
        .onAppear {
            name = group?.name ?? ""; intent = group?.categoryIntent ?? ""; domains = group?.domains.joined(separator: "\n") ?? ""
            #if os(iOS)
            if let group { selection = Enforcement.selection(model.state.selections[group.id.uuidString]) }
            #endif
        }
    }
}
