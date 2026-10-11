import Photos
import SwiftUI
import UIKit

struct LibraryView: View {
    @Bindable var store: LibraryStore
    @AppStorage("libraryLayout") private var layout = LibraryLayout.continuous
    @State private var showingHidden = false
    @State private var query = ""
    @State private var appliedQuery = ""
    @State private var searching = false
    @State private var filter: TagFilter = .all
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var sheet: LibrarySheet?
    @State private var openedID: String?
    @State private var confirmingDelete = false
    @State private var deletionError: String?

    private var results: [Screenshot] { store.filtered(query: appliedQuery, filter: filter, showingHidden: showingHidden) }
    private var resultCount: String { results.count.formatted() }
    private var authorized: Bool { store.permission == .authorized || store.permission == .limited }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = store.indexError {
                    ContentUnavailableView {
                        Label("Index unavailable", systemImage: "externaldrive")
                    } description: { Text(error) } actions: {
                        Button("Retry") { Task { await store.start() } }
                    }
                } else if authorized {
                    if store.aiMessage != nil {
                        Button { sheet = .settings } label: {
                            HStack {
                                Label("Automatic tags unavailable", systemImage: "exclamationmark.circle")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("View how to enable automatic tags")
                    }
                    filters
                    content
                } else {
                    permissionView
                }
            }
            .background(Color.shotsBackground)
            .navigationTitle(selecting ? "\(selection.count) selected" : (showingHidden ? "Hidden" : "Shotr"))
            .navigationSubtitle(authorized && store.isReady ? resultCount : "")
            .toolbarTitleDisplayMode(.inlineLarge)
            .modifier(ScreenshotSearch(query: $query, searching: $searching, enabled: authorized && store.isReady && !selecting))
            .toolbar {
                if authorized && store.isReady && !selecting {
                    ToolbarItem(placement: .bottomBar) { Spacer() }
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selecting {
                        Button("Done") { selecting = false; selection.removeAll() }
                    } else {
                        Menu {
                            if authorized && store.isReady {
                                Button("Select", systemImage: "checkmark.circle") { selecting = true }
                                    .disabled(results.isEmpty)
                                if !showingHidden {
                                    Button("Rescan all", systemImage: "arrow.clockwise") { store.rescan() }
                                        .disabled(!store.hasVisibleItems)
                                }
                                Divider()
                                Picker("Layout", selection: $layout) {
                                    ForEach(LibraryLayout.allCases) { style in
                                        Text(style.rawValue).tag(style)
                                    }
                                }
                                Button(showingHidden ? "Show library" : "Hidden screenshots", systemImage: showingHidden ? "photo.on.rectangle" : "eye.slash") {
                                    showingHidden.toggle()
                                    selection.removeAll()
                                }
                                Divider()
                            }
                            if store.isReady {
                                Button("Tags", systemImage: "tag") { sheet = .tags }
                            }
                            Button("Settings", systemImage: "gearshape") { sheet = .settings }
                            if store.permission == .limited {
                                Button("Photos access", systemImage: "photo.badge.plus") {
                                    store.photos.presentLimitedLibraryPicker()
                                }
                            }
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("More")
                    }
                }
                if selecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            sheet = .assignment
                        } label: { Image(systemName: "tag") }
                        .accessibilityLabel("Tag selected screenshots")
                        .disabled(selection.isEmpty)
                        Spacer()
                        if !showingHidden {
                            Button {
                                store.rescan(ids: selection)
                                selecting = false; selection.removeAll()
                            } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Rescan selected screenshots")
                            .disabled(selection.isEmpty)
                            Spacer()
                        }
                        Button {
                            store.setHidden(!showingHidden, ids: selection)
                            selection.removeAll(); selecting = false
                        } label: { Image(systemName: showingHidden ? "eye" : "eye.slash") }
                        .accessibilityLabel(showingHidden ? "Unhide selected screenshots" : "Hide selected screenshots")
                        .disabled(selection.isEmpty)
                        Spacer()
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete selected screenshots")
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ScanProgressView(store: store, authorized: authorized)
            }
            .sheet(item: $sheet) { presented in
                switch presented {
                case .tags: TagManagerView(store: store)
                case .settings: SettingsView(store: store)
                case .assignment: TagAssignmentView(store: store, ids: selection)
                }
            }
            .fullScreenCover(isPresented: Binding(get: { openedID != nil }, set: { if !$0 { openedID = nil } })) {
                if let id = openedID { ScreenshotDetailView(store: store, id: id, galleryIDs: results.map(\.id), showingHidden: showingHidden) }
            }
            .confirmationDialog("Delete \(selection.count) screenshots from Photos?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete from Photos", role: .destructive) {
                    let ids = selection
                    Task {
                        do {
                            try await store.delete(ids: ids)
                            selection.removeAll(); selecting = false
                        } catch { deletionError = error.localizedDescription }
                    }
                }
            } message: {
                Text("This also removes them from your synced Photos library.")
            }
            .alert("Unable to delete", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button("OK") { deletionError = nil }
            } message: { Text(deletionError ?? "") }
            .alert("Shotr", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
                Button("OK") { store.notice = nil }
            } message: { Text(store.notice ?? "") }
            .onChange(of: store.tags.map(\.id)) { _, ids in
                if case .tag(let id) = filter, !ids.contains(id) { filter = .all }
            }
            .onChange(of: selecting ? results.map(\.id) : []) { _, ids in
                selection.formIntersection(Set(ids))
            }
            .task(id: query) {
                // Don't walk a large OCR index for every intermediate keystroke.
                if !query.isEmpty {
                    do {
                        try await Task.sleep(for: .milliseconds(180))
                        try await store.prepareSearch()
                    }
                    catch { return }
                }
                guard !Task.isCancelled else { return }
                appliedQuery = query
            }
        }
        .tint(Color.primary)
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterButton("All", icon: "square.grid.2x2", value: .all)
                filterButton("Favorites", icon: "heart", value: .favorites)
                filterButton("Untagged", icon: "tag.slash", value: .untagged)
                ForEach(store.tags) { tag in filterButton(tag.name, icon: tag.icon.id, value: .tag(tag.id)) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func filterButton(_ name: String, icon: String, value: TagFilter) -> some View {
        Button { filter = value } label: {
            Label(name, systemImage: icon).font(.subheadline.weight(filter == value ? .semibold : .regular))
                .padding(.horizontal, 13).frame(minHeight: 44)
                .background(filter == value ? Color.primary.opacity(0.12) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == value ? [.isSelected] : [])
    }

    @ViewBuilder private var content: some View {
        if store.isLoading && !store.hasVisibleItems {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView {
                Label(showingHidden ? "No hidden screenshots" : (!store.hasVisibleItems ? "No screenshots" : "No results"), systemImage: showingHidden ? "eye.slash" : "photo")
            } description: {
                if showingHidden {
                    Text("Hidden items stay in Photos. Unhide them here to return them to your library.")
                } else if !store.hasVisibleItems {
                    Text(store.permission == .limited ? "Allow more photos to find your screenshots." : "Your screenshots will appear here.")
                }
            } actions: {
                if store.permission == .limited {
                    Button("Choose photos") { store.photos.presentLimitedLibraryPicker() }
                }
            }
        } else {
            GeometryReader { proxy in
                ScreenshotCollectionGrid(items: results,
                                         days: layout == .byDay ? store.dayGroups(query: appliedQuery, filter: filter, showingHidden: showingHidden) : nil,
                                         width: proxy.size.width, selecting: selecting, selection: selection,
                                         networkAllowed: store.downloadFromICloud,
                                         thumbnail: { item, side in AnyView(thumbnail(item, side: side)) },
                                         refresh: { await store.refresh() })
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }


    private func thumbnail(_ item: Screenshot, side: CGFloat) -> some View {
        Button {
            if selecting {
                if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            } else { openedID = item.id }
        } label: {
            ScreenshotThumbnail(photos: store.photos, item: item, side: side, networkAllowed: store.downloadFromICloud)
                .overlay(alignment: .bottomTrailing) {
                    if selecting {
                        Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).symbolRenderingMode(.palette)
                            .foregroundStyle(selection.contains(item.id) ? Color.black : Color.white, Color.white)
                            .shadow(radius: 2).padding(7)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title.isEmpty ? "Screenshot" : item.title)
        .accessibilityIdentifier("screenshot-\(item.id)")
        .accessibilityValue(item.createdAt.formatted(date: .abbreviated, time: .shortened))
        .accessibilityAddTraits(selection.contains(item.id) ? [.isSelected] : [])
            .contextMenu {
                Button(item.favoritedAt == nil ? "Favorite" : "Unfavorite", systemImage: item.favoritedAt == nil ? "heart" : "heart.fill") {
                    store.setFavorite(item.favoritedAt == nil, ids: [item.id])
                }
                if !showingHidden {
                    Button("Rescan", systemImage: "arrow.clockwise") { store.rescan(ids: [item.id]) }
                }
                Button(showingHidden ? "Unhide" : "Hide", systemImage: showingHidden ? "eye" : "eye.slash") {
                    store.setHidden(!showingHidden, ids: [item.id])
                }
            }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("Your screenshots", systemImage: "photo.on.rectangle")
        } description: {
            Text("Allow Photos access to organize and search your screenshots on this iPhone.")
        } actions: {
            if store.permission == .notDetermined {
                Button("Allow Photos") { Task { await store.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            } else if store.permission == .restricted {
                Text("Photos access is restricted on this iPhone.").font(.footnote)
            } else {
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
        }
    }
}

/// UICollectionView only mounts the visible cells, even with thousands of days
/// and images. SwiftUI still owns the thumbnail actions and selection state.
private struct ScreenshotCollectionGrid: UIViewRepresentable {
    let items: [Screenshot]
    let days: [ScreenshotDay]?
    let width: CGFloat
    let selecting: Bool
    let selection: Set<String>
    let networkAllowed: Bool
    let thumbnail: (Screenshot, CGFloat) -> AnyView
    let refresh: () async -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: Self.layout(grouped: days != nil))
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.contentInsetAdjustmentBehavior = .never
        view.accessibilityIdentifier = "screenshotGrid"
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "screenshot")
        view.register(DayHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: "dayHeader")
        view.dataSource = context.coordinator
        view.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UICollectionView, _: UITraitCollection) in
            view.collectionViewLayout.invalidateLayout()
        }
        let control = UIRefreshControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        view.refreshControl = control
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let previous = coordinator.parent
        let groupedChanged = (coordinator.parent.days != nil) != (days != nil)
        let newIDs = days.map { $0.map { $0.screenshots.map(\.id) } } ?? [items.map(\.id)]
        let dayIDs = days?.map(\.id) ?? []
        let structureChanged = coordinator.ids != newIDs || coordinator.dayIDs != dayIDs
        coordinator.parent = self
        coordinator.ids = newIDs
        coordinator.dayIDs = dayIDs
        if groupedChanged { view.setCollectionViewLayout(Self.layout(grouped: days != nil), animated: false) }
        if structureChanged || groupedChanged {
            view.reloadData()
        } else {
            // An OCR/title/tag change must not reset scrolling or reload 15k cells.
            for path in view.indexPathsForVisibleItems {
                let old = previous.item(at: path)
                let new = item(at: path)
                let needsUpdate = old.title != new.title || old.createdAt != new.createdAt || old.modifiedAt != new.modifiedAt
                    || previous.selecting != selecting || previous.selection.contains(new.id) != selection.contains(new.id)
                    || previous.networkAllowed != networkAllowed || previous.width != width
                if needsUpdate, let cell = view.cellForItem(at: path) { coordinator.configure(cell, at: path, in: view) }
            }
        }
    }

    private func item(at path: IndexPath) -> Screenshot {
        days?[path.section].screenshots[path.item] ?? items[path.item]
    }

    private static func layout(grouped: Bool) -> UICollectionViewLayout {
        if grouped { return DayGridLayout() }
        return UICollectionViewCompositionalLayout { _, environment in
            let side = max(1, (environment.container.effectiveContentSize.width - 4) / 3)
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(side), heightDimension: .absolute(side)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side)), repeatingSubitem: item, count: 3)
            group.interItemSpacing = .fixed(2)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 2
            return section
        }
    }

    /// Compositional boundary pinning is constrained by the outgoing section's
    /// item extent. At a handoff that can release the header before its successor
    /// reaches the viewport, exposing the last screenshot row above the date.
    /// Here the *next header's origin* is the only push-off boundary. Adjacent
    /// headers therefore share an edge throughout the transition, regardless of
    /// how many cells occupy the final row. Cells remain lazily requested/reused.
    private final class DayGridLayout: UICollectionViewLayout {
        private var geometry = DayGridGeometry(width: 0, counts: [], headerHeight: 0)
        private var metricsDirty = true
        private var contentSizeCategory: UIContentSizeCategory?

        override func prepare() {
            super.prepare()
            guard let view = collectionView else { return }
            let category = view.traitCollection.preferredContentSizeCategory
            if metricsDirty || geometry.width != view.bounds.width || contentSizeCategory != category {
                let headline = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: view.traitCollection)
                let subheadline = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: view.traitCollection)
                let scale = max(1, view.traitCollection.displayScale)
                let height = ceil((max(headline.lineHeight, subheadline.lineHeight) + 28) * scale) / scale
                geometry = DayGridGeometry(width: view.bounds.width,
                                           counts: (0..<view.numberOfSections).map { view.numberOfItems(inSection: $0) },
                                           headerHeight: height)
                contentSizeCategory = category
                metricsDirty = false
            }
            #if DEBUG
            let top = view.bounds.minY + view.adjustedContentInset.top
            if let section = geometry.section(at: top) {
                let frame = geometry.headerFrame(section: section, viewportTop: top)
                let next = section + 1 < geometry.starts.count ? geometry.starts[section + 1] : geometry.height
                // Text-only evidence for fixture tests; no screenshot/Photos data.
                view.accessibilityValue = "offset=\(top); headerHeight=\(geometry.headerHeight); pinnedSection=\(section); pinnedY=\(frame.minY - top); nextHeaderY=\(next - top)"
            }
            #endif
        }

        override var collectionViewContentSize: CGSize {
            CGSize(width: geometry.width, height: geometry.height)
        }

        override func invalidateLayout() {
            metricsDirty = true
            super.invalidateLayout()
        }

        override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
            if context.invalidateEverything || context.invalidateDataSourceCounts { metricsDirty = true }
            super.invalidateLayout(with: context)
        }

        override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }

        override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
            guard let view = collectionView,
                  let first = geometry.section(at: rect.minY),
                  let last = geometry.section(at: rect.maxY) else { return [] }
            let top = view.bounds.minY + view.adjustedContentInset.top
            var attributes: [UICollectionViewLayoutAttributes] = []
            for section in first...last {
                appendHeader(section: section, top: top, rect: rect, to: &attributes)
                let count = geometry.counts[section]
                guard count > 0 else { continue }
                let bodyY = geometry.starts[section] + geometry.headerHeight
                let firstRow = max(0, Int(floor((rect.minY - bodyY) / geometry.stride)))
                let lastRow = min((count - 1) / 3, Int(floor((rect.maxY - bodyY) / geometry.stride)))
                guard firstRow <= lastRow else { continue }
                for item in (firstRow * 3)..<min(count, (lastRow + 1) * 3) {
                    let attribute = layoutAttributesForItem(at: IndexPath(item: item, section: section))!
                    if attribute.frame.intersects(rect) { attributes.append(attribute) }
                }
            }
            // A caller may ask for a rect below the viewport. Include the pinned
            // header if its displaced frame intersects that rect, not just when
            // its original section happens to intersect it.
            if let pinned = geometry.section(at: top), !(first...last).contains(pinned) {
                appendHeader(section: pinned, top: top, rect: rect, to: &attributes)
            }
            return attributes
        }

        private func appendHeader(section: Int, top: CGFloat, rect: CGRect,
                                  to attributes: inout [UICollectionViewLayoutAttributes]) {
            let attribute = headerAttributes(section: section, top: top)
            if attribute.frame.intersects(rect) { attributes.append(attribute) }
        }

        override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
            guard geometry.counts.indices.contains(indexPath.section),
                  (0..<geometry.counts[indexPath.section]).contains(indexPath.item) else { return nil }
            let attribute = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attribute.frame = geometry.itemFrame(at: indexPath)
            return attribute
        }

        override func layoutAttributesForSupplementaryView(ofKind elementKind: String,
                                                           at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
            guard elementKind == UICollectionView.elementKindSectionHeader,
                  geometry.starts.indices.contains(indexPath.section), let view = collectionView else { return nil }
            return headerAttributes(section: indexPath.section, top: view.bounds.minY + view.adjustedContentInset.top)
        }

        private func headerAttributes(section: Int, top: CGFloat) -> UICollectionViewLayoutAttributes {
            let attribute = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                with: IndexPath(item: 0, section: section))
            attribute.frame = geometry.headerFrame(section: section, viewportTop: top)
            attribute.zIndex = 1_024 + section
            return attribute
        }
    }

    /// O(days) metrics on data/width/type-size changes; O(log days + visible cells)
    /// per scroll. No cached attributes or scan of the 15,000-item library.
    private struct DayGridGeometry {
        let width: CGFloat
        let counts: [Int]
        let headerHeight: CGFloat
        let side: CGFloat
        let starts: [CGFloat]
        let height: CGFloat
        var stride: CGFloat { side + 2 }

        init(width: CGFloat, counts: [Int], headerHeight: CGFloat) {
            self.width = width
            self.counts = counts
            self.headerHeight = headerHeight
            side = max(1, (width - 4) / 3)
            var starts: [CGFloat] = []
            var y: CGFloat = 0
            for count in counts {
                starts.append(y)
                let rows = (count + 2) / 3
                y += headerHeight + CGFloat(rows) * side + CGFloat(max(0, rows - 1)) * 2
            }
            self.starts = starts
            height = y
        }

        func section(at y: CGFloat) -> Int? {
            guard !starts.isEmpty else { return nil }
            var low = 0
            var high = starts.count
            while low < high {
                let mid = (low + high) / 2
                if starts[mid] <= y { low = mid + 1 } else { high = mid }
            }
            return max(0, low - 1)
        }

        func headerFrame(section: Int, viewportTop: CGFloat) -> CGRect {
            let naturalY = starts[section]
            let nextY = section + 1 < starts.count ? starts[section + 1] : CGFloat.infinity
            let y = min(max(naturalY, viewportTop), nextY - headerHeight)
            return CGRect(x: 0, y: y, width: width, height: headerHeight)
        }

        func itemFrame(at path: IndexPath) -> CGRect {
            CGRect(x: CGFloat(path.item % 3) * stride,
                   y: starts[path.section] + headerHeight + CGFloat(path.item / 3) * stride,
                   width: side, height: side)
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource {
        var parent: ScreenshotCollectionGrid
        var ids: [[String]]
        var dayIDs: [Date]

        init(_ parent: ScreenshotCollectionGrid) {
            self.parent = parent
            ids = parent.days.map { $0.map { $0.screenshots.map(\.id) } } ?? [parent.items.map(\.id)]
            dayIDs = parent.days?.map(\.id) ?? []
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int { parent.days?.count ?? 1 }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.days?[section].screenshots.count ?? parent.items.count
        }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "screenshot", for: indexPath)
            configure(cell, at: indexPath, in: collectionView)
            return cell
        }
        func configure(_ cell: UICollectionViewCell, at path: IndexPath, in view: UICollectionView) {
            let record = parent.item(at: path)
            let side = max(1, (parent.width - 4) / 3)
            let content = parent.thumbnail(record, side)
            cell.contentConfiguration = UIHostingConfiguration { content.id(record.id) }.margins(.all, 0)
        }
        func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "dayHeader", for: indexPath) as! DayHeader
            if let day = parent.days?[indexPath.section] { header.configure(day) }
            return header
        }
        @objc func refresh(_ control: UIRefreshControl) {
            Task { @MainActor in
                await parent.refresh()
                control.endRefreshing()
            }
        }
    }

    private final class DayHeader: UICollectionReusableView {
        private let date = UILabel()
        private let count = UILabel()
        private let edgeCover = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? .black : .systemBackground }
            isOpaque = true
            clipsToBounds = false
            // A single physical-pixel bleed prevents fractional adjacent frames
            // from producing an antialiased seam. It does not change the header
            // or label geometry, nor conceal any meaningful screenshot area.
            edgeCover.backgroundColor = backgroundColor
            edgeCover.isOpaque = true
            edgeCover.isUserInteractionEnabled = false
            addSubview(edgeCover)
            date.font = .preferredFont(forTextStyle: .headline)
            count.font = .preferredFont(forTextStyle: .subheadline)
            count.textColor = .secondaryLabel
            date.adjustsFontForContentSizeCategory = true
            count.adjustsFontForContentSizeCategory = true
            let stack = UIStackView(arrangedSubviews: [date, UIView(), count])
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
            ])
            isAccessibilityElement = true
            accessibilityIdentifier = "dayHeader"
            accessibilityTraits = .header
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            edgeCover.frame = bounds.insetBy(dx: 0, dy: -1 / max(1, traitCollection.displayScale))
        }
        func configure(_ day: ScreenshotDay) {
            date.text = day.id.formatted(date: .abbreviated, time: .omitted)
            count.text = day.screenshots.count.formatted()
            accessibilityLabel = "\(date.text ?? ""), \(day.screenshots.count)"
        }
    }
}

/// Keep elapsed-time and stage updates out of the 15,000-item gallery's body.
private struct ScanProgressView: View {
    let store: LibraryStore
    let authorized: Bool

    private var statusSuffix: String {
        if let reason = store.scanPauseReason {
            switch reason {
            case .user: return " paused"
            case .system: return " paused by iOS"
            case .storage: return " paused · Couldn’t save index"
            case .authorization: return " · Waiting for Photos access"
            }
        }
        if store.isScanning { return "" }
        if store.isRefreshing { return " · Updating library" }
        if store.isScanHandover { return " · Preparing scan" }
        return " · Waiting to start"
    }

    private var canPause: Bool {
        store.scanPauseReason == nil && (store.isScanning || store.isRefreshing || store.isScanHandover)
    }

    var body: some View {
        if authorized && store.scanTotal > store.scanCompleted {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(store.scanPhase.title)\(statusSuffix) · \(store.scanPhaseCompleted.formatted()) of \(store.scanPhaseTotal.formatted())")
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 4) {
                                Text("\(ScanMeasurement.duration(store.scanPhaseElapsed)) elapsed")
                                if store.isScanning, store.scanPauseReason == nil, let remaining = store.estimatedPhaseRemaining {
                                    Text("· About \(ScanMeasurement.duration(remaining)) left")
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            if canPause { store.pauseScan() } else { store.resumeScan() }
                        } label: {
                            Image(systemName: canPause ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(canPause ? "Pause scanning" : "Resume scanning")
                    }
                    ProgressView(value: Double(store.scanPhaseCompleted), total: Double(max(1, store.scanPhaseTotal)))
                        .accessibilityLabel("Scan progress")
                        .accessibilityValue("\(store.scanPhaseCompleted) of \(store.scanPhaseTotal)")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
                .accessibilityIdentifier("scanProgress")
            }
        }
    }
}

private enum LibrarySheet: String, Identifiable {
    case tags, settings, assignment
    var id: String { rawValue }
}

private struct ScreenshotSearch: ViewModifier {
    @Binding var query: String
    @Binding var searching: Bool
    let enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, isPresented: $searching, prompt: "Search screenshots")
                .searchToolbarBehavior(.minimize)
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .toolbarBackground(.hidden, for: .bottomBar)
        } else {
            content
        }
    }
}

extension Color {
    static var shotsBackground: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .systemBackground })
    }
}
