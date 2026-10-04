import SwiftUI

struct TagManagerView: View {
    @Bindable var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingTag: Tag?
    @State private var pendingDeletion: Tag?

    var body: some View {
        NavigationStack {
            List {
                if store.tags.isEmpty {
                    ContentUnavailableView("No tags", systemImage: "tag", description: Text("Create a tag for automatic sorting."))
                        .listRowBackground(Color.clear)
                }
                ForEach(store.tags) { tag in
                    Button { editingTag = tag } label: {
                        Label(tag.name, systemImage: tag.icon.id)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityHint("Edit tag name and icon")
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDeletion = tag }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editingTag = tag }
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = tag }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Color.shotsBackground)
            .navigationTitle("Tags").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingTag = Tag(name: "") } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Create tag")
                        .disabled(store.tags.count >= 32)
                }
            }
            .sheet(item: $editingTag) { tag in TagEditorView(store: store, tag: tag) }
            .confirmationDialog("Delete tag?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button("Delete tag", role: .destructive) {
                    if let tag = pendingDeletion { store.deleteTag(id: tag.id) }
                    pendingDeletion = nil
                }
            } message: { Text("Your screenshots stay in Photos.") }
        }
        .tint(Color.primary)
    }
}

struct TagEditorView: View {
    @Bindable var store: LibraryStore
    let tag: Tag
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var iconName: String
    @State private var errorMessage: String?

    init(store: LibraryStore, tag: Tag) {
        self.store = store
        self.tag = tag
        _name = State(initialValue: tag.name)
        _iconName = State(initialValue: tag.icon.id)
    }

    private var existing: Bool { store.tags.contains { $0.id == tag.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                        .accessibilityIdentifier("tagName")
                    NavigationLink {
                        TagIconPicker(selection: $iconName)
                    } label: {
                        HStack {
                            Label("Icon", systemImage: iconName)
                            Spacer()
                            Text(TagIcon.resolve(iconName, for: name).name).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("chooseTagIcon")
                }
            }
            .scrollContentBackground(.hidden).background(Color.shotsBackground)
            .navigationTitle(existing ? "Edit tag" : "New tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            if existing { try store.renameTag(id: tag.id, name: name, iconName: iconName) }
                            else { try store.createTag(name, iconName: iconName) }
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Unable to save tag", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(Color.primary)
    }
}

struct TagIconPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var icons: [TagIcon] {
        TagIcon.all.filter { query.isEmpty || "\($0.name) \($0.category)".localizedStandardContains(query) }
    }
    private var categories: [String] {
        icons.reduce(into: []) { result, icon in
            if !result.contains(icon.category) { result.append(icon.category) }
        }
    }

    var body: some View {
        ScrollView {
            if icons.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                                ForEach(icons.filter { $0.category == category }) { icon in
                                    Button {
                                        selection = icon.id
                                        dismiss()
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: icon.id).font(.title2).frame(height: 30)
                                            Text(icon.name).font(.caption).lineLimit(1).minimumScaleFactor(0.75)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 76)
                                        .background(selection == icon.id ? Color.primary.opacity(0.12) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 16))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(icon.name)
                                    .accessibilityAddTraits(selection == icon.id ? .isSelected : [])
                                }
                            }
                        }
                    }
                }.padding(20)
            }
        }
        .background(Color.shotsBackground)
        .navigationTitle("Icons").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search icons")
    }
}

struct TagAssignmentView: View {
    @Bindable var store: LibraryStore
    let ids: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var managing = false

    var body: some View {
        NavigationStack {
            List {
                if store.tags.isEmpty {
                    ContentUnavailableView("No tags", systemImage: "tag")
                        .listRowBackground(Color.clear)
                }
                ForEach(store.tags) { tag in
                    let assignments = ids.compactMap { store.screenshot(id: $0) }.map { store.effectiveTags(for: $0).contains(tag.id) }
                    let all = !assignments.isEmpty && assignments.allSatisfy { $0 }
                    let some = assignments.contains(true)
                    Button {
                        store.setTag(tag.id, assigned: !all, for: ids)
                    } label: {
                        HStack {
                            Label(tag.name, systemImage: tag.icon.id).foregroundStyle(.primary)
                            Spacer()
                            if some {
                                Image(systemName: all ? "checkmark" : "minus").foregroundStyle(.primary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityValue(all ? "Selected" : some ? "Some selected" : "Not selected")
                }
            }
            .scrollContentBackground(.hidden).background(Color.shotsBackground)
            .navigationTitle("Tags").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { managing = true }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $managing) { TagManagerView(store: store) }
        }
        .tint(Color.primary)
    }
}
