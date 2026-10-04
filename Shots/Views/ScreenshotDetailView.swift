import SwiftUI
import UIKit

struct ScreenshotDetailView: View {
    @Bindable var store: LibraryStore
    let galleryIDs: [String]
    let showingHidden: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String
    @State private var images: [String: UIImage] = [:]
    @State private var imageRequests: [String: String] = [:]
    @State private var loadingError: String?
    @State private var loadingErrorID: String?
    @State private var showingTags = false
    @State private var confirmingDelete = false
    @State private var deletionError: String?
    @State private var reload = 0
    @State private var availableIDs: [String]
    @State private var positions: [String: Int]
    @State private var galleryVersion = 0

    init(store: LibraryStore, id: String, galleryIDs: [String], showingHidden: Bool = false) {
        self.store = store
        self.galleryIDs = galleryIDs
        self.showingHidden = showingHidden
        _selectedID = State(initialValue: id)
        _availableIDs = State(initialValue: galleryIDs)
        _positions = State(initialValue: Dictionary(uniqueKeysWithValues: galleryIDs.enumerated().map { ($0.element, $0.offset) }))
    }

    private var ids: [String] { availableIDs }
    private var item: Screenshot? { store.screenshot(id: selectedID) }
    private var position: Int { positions[selectedID] ?? 0 }
    private var requestID: String { "\(selectedID)-\(item?.modifiedAt?.timeIntervalSince1970 ?? 0)-\(store.downloadFromICloud)-\(reload)" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenshotPager(ids: ids, positions: positions, version: galleryVersion, selection: $selectedID,
                                 images: images, loadingError: loadingErrorID == selectedID ? loadingError : nil,
                                title: { store.screenshot(id: $0)?.title ?? "Screenshot" },
                                retry: { images[selectedID] = nil; reload += 1 })
                .accessibilityIdentifier("galleryPager")
                filmstrip
            }
            .background(Color.black)
            .navigationTitle(item?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "Screenshot")
            .navigationSubtitle("\(min(position + 1, ids.count)) of \(ids.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close screenshot")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(showingHidden ? "Unhide" : "Hide", systemImage: showingHidden ? "eye" : "eye.slash") {
                            store.setHidden(!showingHidden, ids: [selectedID])
                        }
                        if !showingHidden {
                            Button("Rescan", systemImage: "arrow.clockwise") { store.rescan(ids: [selectedID]) }
                        }
                        Button("Delete from Photos", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More").accessibilityIdentifier("galleryMore")
                }
                ToolbarItem(placement: .bottomBar) {
                    if let image = images[selectedID] {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Screenshot", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share screenshot")
                        .accessibilityIdentifier("galleryShare")
                    }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button { showingTags = true } label: { Image(systemName: "tag") }
                        .accessibilityLabel("Edit tags")
                        .accessibilityIdentifier("galleryTags")
                }
            }
            .task(id: requestID) { await loadVisibleImages() }
            .onChange(of: store.membershipRevision) { _, _ in updateMembership() }
            .sheet(isPresented: $showingTags) { TagAssignmentView(store: store, ids: [selectedID]) }
            .confirmationDialog("Delete screenshot from Photos?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete from Photos", role: .destructive) {
                    let target = selectedID
                    Task {
                        do { try await store.delete(ids: [target]) }
                        catch { deletionError = error.localizedDescription }
                    }
                }
            } message: { Text("This also removes it from your synced Photos library.") }
            .alert("Unable to delete", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button("OK") { deletionError = nil }
            } message: { Text(deletionError ?? "") }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private var filmstrip: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 5) {
                        ForEach(ids, id: \.self) { id in
                            let screenshot = store.screenshot(id: id)
                            Button { selectedID = id } label: {
                                Group {
                                    if let screenshot {
                                        ScreenshotThumbnail(photos: store.photos, item: screenshot, side: 56,
                                                            networkAllowed: store.downloadFromICloud)
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 56, height: 56)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(id == selectedID ? .white : .clear, lineWidth: 2)
                                }
                                .opacity(id == selectedID ? 1 : 0.65)
                            }
                            .frame(width: 56, height: 56)
                            .buttonStyle(.plain)
                            .accessibilityLabel(screenshot.map { $0.title.isEmpty ? "Screenshot" : $0.title } ?? "Screenshot")
                            .accessibilityIdentifier("filmstrip-\(id)")
                            .accessibilityAddTraits(id == selectedID ? .isSelected : [])
                            .id(id)
                        }
                    }
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, max(0, (geometry.size.width - 56) / 2), for: .scrollContent)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityIdentifier("galleryFilmstrip")
                .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
                .onChange(of: geometry.size.width) { _, _ in proxy.scrollTo(selectedID, anchor: .center) }
                .onChange(of: galleryVersion) { _, _ in proxy.scrollTo(selectedID, anchor: .center) }
                .onChange(of: selectedID) { _, id in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12)
        .frame(height: 88)
    }

    private func updateMembership() {
        let remaining = galleryIDs.filter { store.isVisible(id: $0, showingHidden: showingHidden) }
        guard remaining != availableIDs else { return }
        let previous = position
        availableIDs = remaining
        positions = Dictionary(uniqueKeysWithValues: remaining.enumerated().map { ($0.element, $0.offset) })
        if remaining.isEmpty { dismiss() }
        else if positions[selectedID] == nil { selectedID = remaining[min(previous, remaining.count - 1)] }
        galleryVersion += 1
    }

    @MainActor private func loadVisibleImages() async {
        let current = selectedID
        let ordered = ids
        guard let index = positions[current] else { return }
        let adjacent = [index - 1, index + 1].filter { ordered.indices.contains($0) }.map { ordered[$0] }
        let wanted = Set([current] + adjacent)
        images = images.filter { wanted.contains($0.key) }
        imageRequests = imageRequests.filter { wanted.contains($0.key) }
        loadingError = nil
        loadingErrorID = nil
        for id in [current] + adjacent {
            let key = "\(store.screenshot(id: id)?.modifiedAt?.timeIntervalSince1970 ?? 0)-\(store.downloadFromICloud)"
            if images[id] != nil, imageRequests[id] == key { continue }
            images[id] = nil
            do {
                let image = try await store.photos.image(id: id, targetSize: CGSize(width: 2400, height: 4000),
                                                        networkAllowed: store.downloadFromICloud)
                try Task.checkCancellation()
                images[id] = image
                imageRequests[id] = key
            } catch is CancellationError { return }
            catch {
                if Task.isCancelled { return }
                if id == current {
                    loadingError = error.localizedDescription
                    loadingErrorID = current
                }
            }
        }
    }
}

/// The data source holds IDs, not views. Only visible cells are mounted, and layout
/// attributes are computed arithmetically instead of walking the entire library.
private struct ScreenshotPager: UIViewRepresentable {
    let ids: [String]
    let positions: [String: Int]
    let version: Int
    @Binding var selection: String
    let images: [String: UIImage]
    let loadingError: String?
    let title: (String) -> String
    let retry: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ScreenshotPagingCollectionView {
        let view = ScreenshotPagingCollectionView(frame: .zero, collectionViewLayout: ScreenshotPagingLayout())
        view.backgroundColor = .clear
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.isPrefetchingEnabled = false
        view.accessibilityIdentifier = "galleryPager"
        view.register(ScreenshotPageCell.self, forCellWithReuseIdentifier: "screenshot")
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.selectedIndex = positions[selection] ?? 0
        return view
    }

    func updateUIView(_ view: ScreenshotPagingCollectionView, context: Context) {
        let coordinator = context.coordinator
        let membershipChanged = coordinator.parent.version != version
        let selectionChanged = coordinator.selectedID != selection
        coordinator.parent = self
        coordinator.selectedID = selection
        view.selectedIndex = positions[selection] ?? 0
        if membershipChanged {
            view.reloadData()
        }
        if membershipChanged || selectionChanged {
            // Thumbnail taps and hide/delete changes should also interrupt a swipe.
            view.positionSelectedPage()
        }
        for case let cell as ScreenshotPageCell in view.visibleCells {
            guard let index = view.indexPath(for: cell)?.item, ids.indices.contains(index) else { continue }
            coordinator.configure(cell, at: index)
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: ScreenshotPager
        var selectedID: String

        init(_ parent: ScreenshotPager) {
            self.parent = parent
            selectedID = parent.selection
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { parent.ids.count }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "screenshot", for: indexPath) as! ScreenshotPageCell
            configure(cell, at: indexPath.item)
            return cell
        }

        func configure(_ cell: ScreenshotPageCell, at index: Int) {
            let id = parent.ids[index]
            cell.configure(id: id, image: parent.images[id], title: parent.title(id),
                           error: id == parent.selection ? parent.loadingError : nil,
                           retry: parent.retry)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { selectVisiblePage(in: scrollView) }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { selectVisiblePage(in: scrollView) }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { selectVisiblePage(in: scrollView) }
        }

        private func selectVisiblePage(in scrollView: UIScrollView) {
            guard !parent.ids.isEmpty, scrollView.bounds.width > 0 else { return }
            let index = min(max(Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded()), 0), parent.ids.count - 1)
            (scrollView as? ScreenshotPagingCollectionView)?.selectedIndex = index
            let id = parent.ids[index]
            selectedID = id
            if parent.selection != id { parent.selection = id }
        }
    }
}

private final class ScreenshotPagingCollectionView: UICollectionView {
    var selectedIndex = 0
    private var previousSize = CGSize.zero
    private var needsPositioning = true

    func positionSelectedPage() {
        needsPositioning = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        let sizeChanged = previousSize != bounds.size
        if sizeChanged {
            previousSize = bounds.size
            collectionViewLayout.invalidateLayout()
        }
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, sizeChanged || needsPositioning else { return }
        needsPositioning = false
        let index = min(max(selectedIndex, 0), max(0, numberOfItems(inSection: 0) - 1))
        setContentOffset(CGPoint(x: CGFloat(index) * bounds.width, y: 0), animated: false)
    }
}

private final class ScreenshotPagingLayout: UICollectionViewLayout {
    override var collectionViewContentSize: CGSize {
        guard let view = collectionView else { return .zero }
        return CGSize(width: view.bounds.width * CGFloat(view.numberOfItems(inSection: 0)), height: view.bounds.height)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let view = collectionView, view.bounds.width > 0 else { return [] }
        let count = view.numberOfItems(inSection: 0)
        let first = max(0, Int(floor(rect.minX / view.bounds.width)))
        let last = min(count - 1, Int(floor(rect.maxX / view.bounds.width)))
        guard first <= last else { return [] }
        return (first...last).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let view = collectionView else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(x: CGFloat(indexPath.item) * view.bounds.width, y: 0,
                                  width: view.bounds.width, height: view.bounds.height)
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
    }
}

private final class ScreenshotPageCell: UICollectionViewCell {
    private let imageScrollView = ScreenshotScrollView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let errorStack = UIStackView()
    private var representedID: String?
    private var retry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageScrollView)
        spinner.color = .white
        contentView.addSubview(spinner)
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.textColor = .white
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        retryButton.setTitle("Retry", for: .normal)
        retryButton.tintColor = .white
        retryButton.accessibilityIdentifier = "galleryRetry"
        retryButton.addTarget(self, action: #selector(retryImage), for: .touchUpInside)
        errorStack.axis = .vertical
        errorStack.spacing = 12
        errorStack.addArrangedSubview(errorLabel)
        errorStack.addArrangedSubview(retryButton)
        contentView.addSubview(errorStack)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageScrollView.frame = contentView.bounds
        spinner.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        let width = max(0, min(420, contentView.bounds.width - 48))
        let size = errorStack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                    withHorizontalFittingPriority: .required,
                                                    verticalFittingPriority: .fittingSizeLevel)
        errorStack.frame = CGRect(x: (contentView.bounds.width - width) / 2,
                                  y: (contentView.bounds.height - size.height) / 2,
                                  width: width, height: size.height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedID = nil
        retry = nil
        imageScrollView.clearImage()
        spinner.stopAnimating()
        errorStack.isHidden = true
    }

    func configure(id: String, image: UIImage?, title: String, error: String?, retry: @escaping () -> Void) {
        if representedID != id { imageScrollView.clearImage() }
        representedID = id
        self.retry = retry
        imageScrollView.accessibilityLabel = title
        imageScrollView.accessibilityIdentifier = "galleryImage-\(id)"
        imageScrollView.isHidden = image == nil
        if let image { imageScrollView.setImage(image) }
        else { imageScrollView.clearImage() }
        errorStack.isHidden = image != nil || error == nil
        errorLabel.text = error
        if image == nil && error == nil { spinner.startAnimating() }
        else { spinner.stopAnimating() }
        setNeedsLayout()
    }

    @objc private func retryImage() { retry?() }
}

private final class ScreenshotScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var previousSize = CGSize.zero
    private var needsFit = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        bouncesZoom = true
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        guard imageView.image !== image else { return }
        minimumZoomScale = 1
        maximumZoomScale = 1
        setZoomScale(1, animated: false)
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        needsFit = true
        setNeedsLayout()
    }

    func clearImage() {
        guard imageView.image != nil else { return }
        imageView.image = nil
        minimumZoomScale = 1
        maximumZoomScale = 1
        setZoomScale(1, animated: false)
        contentSize = .zero
        contentInset = .zero
        needsFit = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        if needsFit || previousSize != bounds.size {
            previousSize = bounds.size
            needsFit = false
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            maximumZoomScale = max(fit * 6, 1)
            minimumZoomScale = fit
            setZoomScale(fit, animated: false)
        }
        centerImage()
        updatePanning()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        updatePanning()
    }

    private func updatePanning() {
        // At fit size, horizontal drags belong to the outer page collection view.
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale * 1.05
    }

    private func centerImage() {
        let x = max(0, (bounds.width - imageView.frame.width) / 2)
        let y = max(0, (bounds.height - imageView.frame.height) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != inset { contentInset = inset }
    }

    @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.05 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let scale = min(maximumZoomScale, minimumZoomScale * 3)
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
