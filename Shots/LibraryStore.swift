import Foundation
import Observation
import Photos
import UIKit

enum Appearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

enum ScanPhase {
    case indexing, describing, discovering, tagging

    var title: String {
        switch self {
        case .indexing: "Indexing screenshots"
        case .describing: "Describing screenshots"
        case .discovering: "Discovering categories"
        case .tagging: "Adding automatic tags"
        }
    }
}

@Observable @MainActor
final class LibraryStore {
    private(set) var tags: [Tag] = [] {
        didSet {
            allowedTagIDs = Set(tags.map(\.id))
            libraryRevision += 1
        }
    }
    private(set) var permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var isLoading = true
    private(set) var isScanning = false
    // Overall counters count each screenshot once (after AI, or OCR when AI is
    // unavailable). The progress view should use phase counters during indexing.
    private(set) var scanCompleted = 0
    private(set) var scanTotal = 0
    private(set) var scanPhase = ScanPhase.indexing
    private(set) var indexCompleted = 0
    private(set) var indexTotal = 0
    private(set) var tagCompleted = 0
    private(set) var tagTotal = 0
    private(set) var descriptionCompleted = 0
    private(set) var descriptionTotal = 0
    private var descriptionElapsed: TimeInterval = 0
    private var indexElapsed: TimeInterval = 0
    private var tagElapsed: TimeInterval = 0
    private var phaseStartedUptime: TimeInterval?
    private(set) var scanMeasurement = ScanMeasurement()
    private(set) var lastScan: ScanMeasurement?
    private var scanStartedUptime: TimeInterval?
    @ObservationIgnored private var scanAttemptedIDs: Set<String> = []
    @ObservationIgnored private var indexAttemptedIDs: Set<String> = []
    @ObservationIgnored private var resetTimingOnNextScan = false

    var scanElapsed: TimeInterval {
        scanMeasurement.elapsed + (scanStartedUptime.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0)
    }

    var scanPhaseCompleted: Int {
        switch scanPhase {
        case .indexing: indexCompleted
        case .describing: descriptionCompleted
        case .discovering: 0
        case .tagging: tagCompleted
        }
    }
    var scanPhaseTotal: Int {
        switch scanPhase {
        case .indexing: indexTotal
        case .describing: descriptionTotal
        case .discovering: 1
        case .tagging: tagTotal
        }
    }
    var scanPhaseElapsed: TimeInterval {
        (scanPhase == .indexing ? indexElapsed : scanPhase == .describing ? descriptionElapsed : tagElapsed) +
            (phaseStartedUptime.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0)
    }
    var estimatedPhaseRemaining: TimeInterval? {
        let elapsed = scanPhaseElapsed
        guard scanPhaseCompleted >= 3, scanPhaseTotal > scanPhaseCompleted, elapsed > 0 else { return nil }
        return elapsed / Double(scanPhaseCompleted) * Double(scanPhaseTotal - scanPhaseCompleted)
    }
    private(set) var aiMessage: String?
    var notice: String?
    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    var downloadFromICloud: Bool {
        didSet {
            UserDefaults.standard.set(downloadFromICloud, forKey: "downloadFromICloud")
            if isReady { resetTimingOnNextScan = true; restartScan() }
        }
    }

    let photos: PhotosClient
    // Observe a cheap revision rather than the entire dictionary. Observable
    // dictionary mutations otherwise copy its storage through generated accessors.
    @ObservationIgnored private var records: [String: Screenshot] = [:]
    private var visibleIDs: [String] = [] {
        didSet {
            visibleIDSet = Set(visibleIDs)
            libraryRevision += 1
        }
    }
    private var libraryRevision = 0
    private(set) var membershipRevision = 0
    @ObservationIgnored private var visibleIDSet: Set<String> = []
    @ObservationIgnored private var allowedTagIDs: Set<UUID> = []
    @ObservationIgnored private var resultCache: LibraryResultCache?
    private var tagRevision = 1
    private var categoryDiscoveryCount: Int?
    private var categoryDiscoveryCompleted = false
    private var dismissedCategoryNames: [String] = []
    @ObservationIgnored private let disk = IndexDisk()
    @ObservationIgnored private let analyzer = ImageAnalyzer()
    @ObservationIgnored private let tagger = LocalTagger()
    @ObservationIgnored private let backgroundScan = BackgroundScanCoordinator.shared
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanIdentity: UUID?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var saveSequence = 0
    @ObservationIgnored private var persistedRevision = -1
    @ObservationIgnored private var lastCheckpointUptime = ProcessInfo.processInfo.systemUptime
    private(set) var isReady = false
    private(set) var indexError: String?
    private var persistenceFailed = false
    @ObservationIgnored private var isStarting = false
    private(set) var isRefreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var refreshGeneration = LibraryRefreshGeneration()
    @ObservationIgnored private var photoSnapshot: [PhotoItem]?
    @ObservationIgnored private var snapshotPermission: PHAuthorizationStatus?
    private var isActive = true
    private var userPaused = false
    private var storagePaused = false
    private var systemPaused = false
    private var scanHandoverCount = 0
    private var restartPending = false
    @ObservationIgnored private var searchCache: [String: CachedSearch] = [:]

    private var scanAllowed: Bool { isActive || backgroundScan.allowsBackgroundScanning }

    /// Do not infer pause from !isScanning: discovery/cancellation/checkpointing
    /// are transitions, not a user or OS pause. A stalled task stays observable
    /// as a real task, rather than being represented by synthetic "running" state.
    var scanPauseReason: ScanPauseReason? {
        if persistenceFailed || storagePaused { return .storage }
        if userPaused { return .user }
        if permission != .authorized && permission != .limited { return .authorization }
        if systemPaused || !scanAllowed { return .system }
        return nil
    }

    var isScanHandover: Bool { scanHandoverCount > 0 || restartPending }

    init() {
        photos = PhotosClient()
        if let data = UserDefaults.standard.data(forKey: "lastScanMeasurement") {
            lastScan = try? JSONDecoder().decode(ScanMeasurement.self, from: data)
        }
        appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        downloadFromICloud = UserDefaults.standard.object(forKey: "downloadFromICloud") as? Bool ?? true
        backgroundScan.install(onStart: { [weak self] in
            guard let self, self.isReady, !self.persistenceFailed,
                  self.photos.authorization == .authorized || self.photos.authorization == .limited else { return false }
            self.resumeScan()
            return true
        }, onStop: { [weak self] in
            guard let self else { return }
            self.systemPaused = true
            self.scanHandoverCount += 1
            defer {
                self.scanHandoverCount -= 1
                self.startScanIfNeeded()
            }
            self.generation += 1
            await self.stopScan()
            await self.persistReportingError()
            // System cancellation and the Live Activity cancel button share this
            // path. Neither changes the user's foreground pause preference.
        })
    }

    var items: [Screenshot] {
        _ = libraryRevision
        return visibleIDs.compactMap { records[$0] }.filter { $0.hiddenAt == nil }
    }
    var hiddenItems: [Screenshot] {
        _ = libraryRevision
        return visibleIDs.compactMap { records[$0] }.filter { $0.hiddenAt != nil }
    }
    var hasVisibleItems: Bool {
        _ = membershipRevision
        return visibleIDs.contains { records[$0].map { $0.hiddenAt == nil } ?? false }
    }

    func setHidden(_ hidden: Bool, ids: Set<String>) {
        guard isReady else { return }
        let hiddenAt = hidden ? Date() : nil
        for id in ids {
            guard var record = records[id], (record.hiddenAt != nil) != hidden else { continue }
            record.hiddenAt = hiddenAt
            updateRecord(record)
        }
        membershipRevision += 1
        if !hidden { resetTimingOnNextScan = true }
        scheduleSave()
        restartScan()
    }

    func setFavorite(_ favorite: Bool, ids: Set<String>) {
        guard isReady else { return }
        for id in ids {
            guard var record = records[id], (record.favoritedAt != nil) != favorite else { continue }
            record.favoritedAt = favorite ? Date() : nil
            updateRecord(record)
        }
        scheduleSave()
    }

    func start() async {
        guard !isReady, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        isLoading = true
        indexError = nil
        do {
            let snapshot = try await disk.load() ?? IndexSnapshot()
            tags = snapshot.tags
            tagRevision = snapshot.tagRevision
            categoryDiscoveryCount = snapshot.categoryDiscoveryCount
            categoryDiscoveryCompleted = snapshot.categoryDiscoveryCompleted ?? false
            dismissedCategoryNames = snapshot.dismissedCategoryNames ?? []
            // Tolerate duplicate IDs without trapping; the newest saved entry wins.
            records = Dictionary(snapshot.screenshots.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            libraryRevision += 1
            persistedRevision = libraryRevision
            isReady = true
            photos.onChange = { [weak self] in
                guard let self else { return }
                // Invalidate immediately, not after the debounce: a fetch already
                // in flight must never apply a snapshot from before this change.
                self.refreshGeneration.invalidate()
                if self.isRefreshing {
                    self.refreshAgain = true
                    return
                }
                self.changeTask?.cancel()
                self.changeTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    // Only the debounce is cancellable by the next notification.
                    // The serialized refresh owns its own invalidation generation.
                    self.changeTask = nil
                    await self.refresh()
                }
            }
            await refresh()
        } catch {
            indexError = "Your saved index has been kept. \(error.localizedDescription)"
        }
        isLoading = false
    }

    func requestAccess() async {
        _ = await photos.requestAccess()
        if !isReady { await start() } else { await refresh() }
    }

    func refresh() async {
        refreshGeneration.invalidate()
        guard isReady, isActive else { return }
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        defer {
            isRefreshing = false
            if !Task.isCancelled { startScanIfNeeded() }
        }
        repeat {
            refreshAgain = false
            let refreshToken = refreshGeneration.current
            let photoToken = photos.libraryChangeRevision
            permission = photos.authorization
            aiMessage = tagger.unavailableReason
            guard permission == .authorized || permission == .limited else {
                // Revoked read access is relevant even without fetch-result changes.
                generation += 1
                await stopScan()
                guard isActive, !Task.isCancelled else { return }
                guard refreshGeneration.accepts(refreshToken, cancelled: Task.isCancelled),
                      photoToken == photos.libraryChangeRevision,
                      permission == photos.authorization else { refreshAgain = true; continue }
                visibleIDs = []
                photoSnapshot = nil
                snapshotPermission = permission
                membershipRevision += 1
                let token = generation
                await persistReportingError()
                if generation == token { backgroundScan.finish(success: false) }
                continue
            }
            // Discovery must not interrupt OCR/AI. Most Photos notifications are
            // irrelevant, and identical snapshots must be a true no-op.
            let assets = await photos.fetchScreenshots()
            guard isActive, !Task.isCancelled else { return }
            if !refreshGeneration.accepts(refreshToken, cancelled: Task.isCancelled) ||
                photoToken != photos.libraryChangeRevision ||
                permission != photos.authorization {
                refreshAgain = true
                continue
            }
            guard snapshotPermission != permission ||
                ScreenshotSnapshotChange.isRelevant(previous: photoSnapshot, fetched: assets) else { continue }
            generation += 1
            await stopScan()
            // Cancellation/checkpointing can suspend too. Newer library changes,
            // scene transitions or read authorization invalidate this snapshot.
            guard isActive, !Task.isCancelled else { return }
            guard refreshGeneration.accepts(refreshToken, cancelled: Task.isCancelled),
                  photoToken == photos.libraryChangeRevision,
                  permission == photos.authorization else { refreshAgain = true; continue }
            let fetchedIDs = assets.map(\.id)
            if visibleIDs != fetchedIDs { visibleIDs = fetchedIDs }
            for asset in assets {
                if var record = records[asset.id] {
                    if record.modifiedAt != asset.modifiedAt {
                        resetTimingOnNextScan = true
                        record.modifiedAt = asset.modifiedAt
                        record.scannedAt = nil
                        record.describedAt = nil
                        categoryDiscoveryCount = nil
                        record.taggedRevision = nil
                    }
                    record.createdAt = asset.createdAt
                    updateRecord(record)
                } else {
                    updateRecord(Screenshot(id: asset.id, createdAt: asset.createdAt, modifiedAt: asset.modifiedAt))
                }
            }
            // Limited access can hide assets without deleting them. Retain their index.
            if permission == .authorized {
                let missing = records.keys.filter { !visibleIDSet.contains($0) }
                if !missing.isEmpty {
                    for id in missing { records.removeValue(forKey: id) }
                    libraryRevision += 1
                    resultCache = nil
                }
            }
            searchCache = searchCache.filter { visibleIDSet.contains($0.key) }
            photoSnapshot = assets
            snapshotPermission = permission
            membershipRevision += 1
            scheduleSave()
        } while refreshAgain && isActive
    }

    func sceneChanged(active: Bool) async {
        refreshGeneration.invalidate()
        let wasActive = isActive
        isActive = active
        if active {
            systemPaused = false
            let handover = !wasActive
            if handover { scanHandoverCount += 1 }
            defer {
                if handover {
                    scanHandoverCount -= 1
                    startScanIfNeeded()
                }
            }
            if handover {
                // Background work was deliberately OCR-only. Foreground tagging
                // needs a new task/mode even when the Photos snapshot is identical.
                generation += 1
                let sceneToken = refreshGeneration.current
                await stopScan()
                guard isActive, refreshGeneration.accepts(sceneToken, cancelled: Task.isCancelled) else { return }
            }
            if isReady { await refresh() } else { await start() }
        } else {
            scanHandoverCount += 1
            defer {
                scanHandoverCount -= 1
                startScanIfNeeded()
            }
            generation += 1
            let token = generation
            await stopScan()
            guard generation == token, !isActive else { return }
            if isReady { await persistReportingError() }
            guard generation == token, !isActive else { return }
            if persistenceFailed || storagePaused || userPaused {
                backgroundScan.finish(success: false)
            }
            // The defer releases the handover and starts an OCR-only task if the
            // OS allowance still exists. All foreground preparation has exited.
        }
    }

    func filtered(query: String, filter: TagFilter, showingHidden: Bool = false) -> [Screenshot] {
        let revision = libraryRevision
        if let cache = resultCache, cache.revision == revision, cache.query == query,
           cache.filter == filter, cache.showingHidden == showingHidden {
            return cache.items
        }
        let currentItems = showingHidden ? hiddenItems : items
        // The ordinary grid needs no text normalization at all. Other searches
        // prepare OCR once per changed record, not on every keystroke.
        let results: [Screenshot]
        // Query folding is independent of the document: do it once, not 15,000 times.
        let terms = SearchNormalization.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.isEmpty, filter == .all {
            results = currentItems
        } else {
            results = currentItems.filter { record in
                matches(record, terms: terms, filter: filter)
            }
        }
        resultCache = LibraryResultCache(revision: revision, query: query, terms: terms, filter: filter,
                                        showingHidden: showingHidden, items: results)
        return results
    }

    /// The first text search can normalize many megabytes of OCR. Warm those
    /// documents on a worker before applying the query, not while rendering UI.
    func prepareSearch() async throws {
        while true {
            try Task.checkCancellation()
            let revision = tagRevision
            let taxonomy = tags
            let pending = visibleIDs.compactMap { id -> Screenshot? in
                guard searchCache[id]?.revision != revision else { return nil }
                return records[id]
            }
            guard !pending.isEmpty else { return }
            let worker = Task.detached(priority: .userInitiated) {
                try pending.map { record in
                    try Task.checkCancellation()
                    return (record, SearchEngine.prepare(record, tags: taxonomy))
                }
            }
            let prepared = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
            guard revision == tagRevision else { continue }
            for (snapshot, document) in prepared where records[snapshot.id] == snapshot && visibleIDSet.contains(snapshot.id) {
                searchCache[snapshot.id] = CachedSearch(revision: revision, document: document)
            }
            return
        }
    }

    func dayGroups(query: String, filter: TagFilter, showingHidden: Bool) -> [ScreenshotDay] {
        let results = filtered(query: query, filter: filter, showingHidden: showingHidden)
        if let groups = resultCache?.days { return groups }
        let groups = ScreenshotDay.groups(results)
        resultCache?.cacheDays(groups)
        return groups
    }

    func screenshot(id: String) -> Screenshot? {
        _ = libraryRevision
        guard visibleIDSet.contains(id) else { return nil }
        return records[id]
    }

    func isVisible(id: String, showingHidden: Bool) -> Bool {
        _ = membershipRevision
        guard visibleIDSet.contains(id), let record = records[id] else { return false }
        return (record.hiddenAt != nil) == showingHidden
    }

    func effectiveTags(for record: Screenshot) -> Set<UUID> {
        _ = tags
        return TagRules.effectiveTags(for: record, allowed: allowedTagIDs)
    }

    private func matches(_ record: Screenshot, terms: [String], filter: TagFilter) -> Bool {
        // Tag-only browsing must never normalize the library's OCR text.
        if terms.isEmpty {
            if filter == .all { return true }
            let effective = TagRules.effectiveTags(for: record, allowed: allowedTagIDs)
            switch filter {
            case .all: return true
            case .favorites: return record.favoritedAt != nil
            case .untagged: return effective.isEmpty
            case .tag(let id): return effective.contains(id)
            }
        }
        let document: PreparedSearchDocument
        if let cached = searchCache[record.id], cached.revision == tagRevision {
            document = cached.document
        } else {
            document = SearchEngine.prepare(record, tags: tags)
            searchCache[record.id] = CachedSearch(revision: tagRevision, document: document)
        }
        switch filter {
        case .all: break
        case .favorites: guard document.isFavorite else { return false }
        case .untagged: guard document.effectiveTagIDs.isEmpty else { return false }
        case .tag(let id): guard document.effectiveTagIDs.contains(id) else { return false }
        }
        return terms.allSatisfy { document.normalizedText.contains($0) }
    }

    /// One changed record must not force a complete search/day regroup. Keep a
    /// warm result's positions when its membership and ordering are unchanged.
    private func updateRecord(_ record: Screenshot) {
        let previous = records[record.id]
        guard previous != record else { return }
        let oldRevision = libraryRevision
        records[record.id] = record
        libraryRevision += 1
        if previous?.title != record.title || previous?.text != record.text || previous?.contentDescription != record.contentDescription ||
            previous?.favoritedAt != record.favoritedAt ||
            previous?.visualLabels != record.visualLabels || previous?.aiTagIDs != record.aiTagIDs ||
            previous?.addedTagIDs != record.addedTagIDs || previous?.removedTagIDs != record.removedTagIDs {
            searchCache.removeValue(forKey: record.id)
        }
        guard let cache = resultCache, cache.revision == oldRevision else { return }
        guard visibleIDSet.contains(record.id) else {
            cache.revision = libraryRevision
            return
        }
        guard let previous, previous.createdAt == record.createdAt else {
            resultCache = nil
            return
        }
        let position = cache.positions[record.id]
        let included = (record.hiddenAt != nil) == cache.showingHidden && matches(record, terms: cache.terms, filter: cache.filter)
        guard included == (position != nil) else {
            resultCache = nil
            return
        }
        if let position { cache.replace(record, at: position) }
        cache.revision = libraryRevision
    }

    func createTag(_ name: String, iconName: String? = nil) throws {
        guard isReady else { throw IndexUnavailableError() }
        guard tags.count < 32 else { throw TagLimitError() }
        let valid = try TagRules.validatedName(name, tags: tags)
        tags.append(Tag(name: valid, iconName: iconName))
        taxonomyChanged()
    }

    func renameTag(id: UUID, name: String, iconName: String? = nil) throws {
        guard isReady else { throw IndexUnavailableError() }
        guard let position = tags.firstIndex(where: { $0.id == id }) else { return }
        let valid = try TagRules.validatedName(name, tags: tags, excluding: id)
        if tags[position].name != valid { dismissedCategoryNames.append(tags[position].name) }
        tags[position].name = valid
        if let iconName { tags[position].iconName = TagIcon.resolve(iconName, for: name).id }
        taxonomyChanged()
    }

    func deleteTag(id: UUID) {
        guard isReady else { return }
        if let tag = tags.first(where: { $0.id == id }) { dismissedCategoryNames.append(tag.name) }
        tags.removeAll { $0.id == id }
        for key in Array(records.keys) {
            guard var record = records[key] else { continue }
            record.aiTagIDs.remove(id)
            record.addedTagIDs.remove(id)
            record.removedTagIDs.remove(id)
            updateRecord(record)
        }
        taxonomyChanged()
    }

    private func taxonomyChanged() {
        // A new taxonomy must revisit items already attempted in an interrupted run.
        resetTimingOnNextScan = true
        tagRevision += 1
        scheduleSave()
        restartScan()
    }

    func setTag(_ tagID: UUID, assigned: Bool, for ids: Set<String>) {
        guard isReady else { return }
        guard tags.contains(where: { $0.id == tagID }) else { return }
        for id in ids {
            guard var record = records[id] else { continue }
            TagRules.set(tagID: tagID, assigned: assigned, on: &record)
            updateRecord(record)
        }
        scheduleSave()
    }

    func rescan(ids: Set<String>? = nil) {
        guard isReady else { return }
        let targets = ids ?? Set(items.map(\.id))
        categoryDiscoveryCount = nil
        for id in targets {
            guard var record = records[id] else { continue }
            record.scannedAt = nil
            record.describedAt = nil
            record.taggedRevision = nil
            record.lastError = nil
            updateRecord(record)
        }
        userPaused = false
        storagePaused = false
        systemPaused = false
        resetTimingOnNextScan = true
        scheduleSave()
        restartScan()
    }

    func pauseScan() {
        userPaused = true
        generation += 1
        scanTask?.cancel()
        let oldTask = scanTask
        Task { [weak self] in
            await oldTask?.value
            guard let self, self.userPaused else { return }
            await self.persistReportingError()
            guard self.userPaused else { return }
            self.backgroundScan.finish(success: false)
        }
    }

    func resumeScan() {
        userPaused = false
        storagePaused = false
        systemPaused = false
        restartScan()
    }

    func delete(ids: Set<String>) async throws {
        try await photos.delete(ids: ids)
        for id in ids { records.removeValue(forKey: id) }
        libraryRevision += 1
        resultCache = nil
        for id in ids { searchCache.removeValue(forKey: id) }
        visibleIDs.removeAll { ids.contains($0) }
        membershipRevision += 1
        await persistReportingError()
        await refresh()
    }

    private func restartScan() {
        generation += 1
        scanTask?.cancel()
        restartPending = true
        // Multiple edits/resume requests share one cancellation waiter; the most
        // recent state is used after the outgoing task's checkpoint has ended.
        guard restartTask == nil else { return }
        let oldTask = scanTask
        let oldIdentity = scanIdentity
        restartTask = Task { [weak self] in
            await oldTask?.value
            guard let self else { return }
            if self.scanIdentity == oldIdentity {
                self.scanTask = nil
                self.scanIdentity = nil
            }
            // Resume is also the explicit retry path after a failed checkpoint.
            // Never enter OCR/AI until that retry succeeds.
            if self.persistenceFailed, !self.userPaused, !self.storagePaused {
                await self.persistReportingError()
            }
            self.restartTask = nil
            self.restartPending = false
            self.startScanIfNeeded()
        }
    }

    private func stopScan() async {
        scanHandoverCount += 1
        defer { scanHandoverCount -= 1 }
        let oldTask = scanTask
        let oldIdentity = scanIdentity
        oldTask?.cancel()
        await oldTask?.value
        // Keep the task visible while awaiting it, so overlapping lifecycle
        // events also wait rather than starting work before cancellation ends.
        if scanIdentity == oldIdentity {
            scanTask = nil
            scanIdentity = nil
        }
    }

    private func startScanIfNeeded() {
        guard isReady, scanAllowed, !systemPaused, !storagePaused, !persistenceFailed,
              !isScanning, scanTask == nil, !isRefreshing, !isScanHandover,
              permission == .authorized || permission == .limited else { return }
        aiMessage = tagger.unavailableReason
        let canTag = isActive && aiMessage == nil
        var candidates = items.filter { $0.scannedAt == nil || (canTag && (needsDescription($0) || $0.taggedRevision != tagRevision)) }.map(\.id)
        if candidates.isEmpty, canTag, categoryDiscoveryIsDue {
            candidates = items.filter { $0.describedAt != nil }.map(\.id)
        }
        guard !candidates.isEmpty else {
            scanCompleted = 0
            scanTotal = 0
            backgroundScan.updateProgress(completed: scanCompleted, total: scanTotal)
            finishEmptyBackgroundScan()
            return
        }
        guard !userPaused else { return }
        let continuing = !resetTimingOnNextScan && scanMeasurement.aiAvailable == canTag && scanTotal > scanCompleted
        if continuing {
            candidates.removeAll { scanAttemptedIDs.contains($0) }
            // Photos can add/remove items during a paused session. Preserve work
            // already counted, but recompute the still-pending phase totals.
            indexTotal = indexCompleted + candidates.reduce(0) {
                $0 + (records[$1]?.scannedAt == nil && !indexAttemptedIDs.contains($1) ? 1 : 0)
            }
            tagTotal = canTag ? tagCompleted + candidates.count : 0
        } else {
            scanMeasurement = ScanMeasurement()
            scanCompleted = 0
            scanAttemptedIDs = []
            indexAttemptedIDs = []
            indexCompleted = 0
            indexTotal = candidates.reduce(0) { $0 + (records[$1]?.scannedAt == nil ? 1 : 0) }
            tagCompleted = 0
            tagTotal = canTag ? candidates.count : 0
            descriptionCompleted = 0
            descriptionTotal = canTag ? candidates.reduce(0) { $0 + (records[$1].map(needsDescription) == true ? 1 : 0) } : 0
            descriptionElapsed = 0
            indexElapsed = 0
            tagElapsed = 0
        }
        resetTimingOnNextScan = false
        scanTotal = scanCompleted + candidates.count
        backgroundScan.updateProgress(completed: scanCompleted, total: scanTotal)
        guard !candidates.isEmpty else {
            finishEmptyBackgroundScan()
            return
        }
        scanMeasurement.aiAvailable = canTag
        scanStartedUptime = ProcessInfo.processInfo.systemUptime
        isScanning = true
        scanIdentity = UUID()
        scanTask = Task { [weak self] in
            await self?.scan(candidates)
        }
    }

    private func scan(_ ids: [String]) async {
        defer {
            finishPhaseTiming()
            scanMeasurement.elapsed = scanElapsed
            scanStartedUptime = nil
            isScanning = false
            scanTask = nil
            scanIdentity = nil
            if scanCompleted == scanTotal, !Task.isCancelled {
                lastScan = scanMeasurement
                if let data = try? JSONEncoder().encode(scanMeasurement) {
                    UserDefaults.standard.set(data, forKey: "lastScanMeasurement")
                }
            }
        }
        var failed = 0
        let indexingIDs = ids.filter { records[$0]?.scannedAt == nil && !indexAttemptedIDs.contains($0) }
        if !indexingIDs.isEmpty { beginPhase(.indexing) }
        // Read the entire library before any model inference. Searchable OCR is
        // saved independently of slower AI enrichment, including on interruption.
        // A single prepared image may overlap the next Photos load with Vision.
        var pending = preparationTask(for: indexingIDs.first)
        for (offset, id) in indexingIDs.enumerated() {
            if Task.isCancelled || !scanAllowed { break }
            let preparation = pending
            pending = preparationTask(for: offset + 1 < indexingIDs.count ? indexingIDs[offset + 1] : nil)
            guard let original = records[id], original.hiddenAt == nil else {
                preparation?.cancel()
                _ = try? await preparation?.value
                continue
            }
            do {
                guard let preparation else { continue }
                let prepared = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: {
                    preparation.cancel()
                }
                scanMeasurement.imageSeconds += prepared.imageSeconds
                scanMeasurement.analysisSeconds += prepared.analysisSeconds
                try Task.checkCancellation()
                // Read the current record so manual changes made during OCR survive.
                if var record = records[id] {
                    record.text = prepared.content.text
                    record.visualLabels = prepared.content.visualLabels
                    record.scannedAt = Date()
                    record.lastError = nil
                    updateRecord(record)
                }
                if !scanMeasurement.aiAvailable { finishScreenshot(id) }
            } catch is CancellationError {
                break
            } catch {
                if Task.isCancelled { break }
                failed += 1
                recordFailure(error, id: id)
                finishScreenshot(id)
            }
            indexCompleted += 1
            indexAttemptedIDs.insert(id)
            reportPhaseProgress()
            if !(await checkpointScanIfNeeded()) { break }
            await Task.yield()
        }
        pending?.cancel()
        _ = try? await pending?.value
        // Commit the search index at the phase boundary, not after thousands of
        // model calls. A save failure must pause before starting enrichment.
        if !Task.isCancelled, scanAllowed, !userPaused, !storagePaused {
            do { try await persist() }
            catch { pauseForSaveError(error) }
        }

        if !Task.isCancelled, isActive, !userPaused, !storagePaused, scanMeasurement.aiAvailable {
            let descriptionIDs = ids.filter { records[$0].map { $0.hiddenAt == nil && $0.scannedAt != nil && needsDescription($0) } == true }
            if descriptionIDs.contains(where: { records[$0]?.descriptionUsesImage == false && tagger.canDescribeImages }) {
                categoryDiscoveryCount = nil
                libraryRevision += 1
            }
            descriptionTotal = descriptionCompleted + descriptionIDs.count
            if !descriptionIDs.isEmpty { beginPhase(.describing) }
            var describedBatch: [String] = []
            for id in descriptionIDs {
                if Task.isCancelled || !isActive || userPaused || storagePaused { break }
                guard let current = records[id], current.hiddenAt == nil else { continue }
                do {
                    let imageData: Data?
                    if tagger.canDescribeImages {
                        let start = ProcessInfo.processInfo.systemUptime
                        imageData = try await photos.analysisData(id: id, networkAllowed: downloadFromICloud)
                        scanMeasurement.imageSeconds += ProcessInfo.processInfo.systemUptime - start
                    } else { imageData = nil }
                    try Task.checkCancellation()
                    let start = ProcessInfo.processInfo.systemUptime
                    let description: ScreenshotDescription
                    do {
                        defer { scanMeasurement.taggingSeconds += ProcessInfo.processInfo.systemUptime - start }
                        description = try await tagger.describe(imageData: imageData, text: current.text, visualLabels: current.visualLabels)
                    }
                    try Task.checkCancellation()
                    if var record = records[id] {
                        record.title = description.title
                        record.contentDescription = description.contentDescription
                        record.descriptionUsesImage = description.usedImage
                        record.describedAt = Date()
                        record.taggedRevision = nil
                        record.lastError = nil
                        updateRecord(record)
                        describedBatch.append(id)
                    }
                } catch is CancellationError { break }
                catch {
                    if Task.isCancelled { break }
                    failed += 1
                    recordFailure(error, id: id)
                    finishScreenshot(id)
                }
                descriptionCompleted += 1
                reportPhaseProgress()
                if !(await checkpointScanIfNeeded()) { break }
                if describedBatch.count >= 32, !Task.isCancelled, isActive, !userPaused, !storagePaused {
                    let revision = tagRevision
                    // Discover early, then revisit at geometrically spaced milestones;
                    // bounded library sampling never runs for every image.
                    if TagRules.scanDiscoveryIsDue(count: describedCount, lastCount: categoryDiscoveryCount,
                                                   completed: categoryDiscoveryCompleted) {
                        do { try await discoverCategoriesIfNeeded() }
                        catch is CancellationError { break }
                        catch { if !Task.isCancelled { notice = "Category discovery couldn’t finish. Saved descriptions are kept; reopen Shots to retry." } }
                    }
                    let batch = revision == tagRevision ? describedBatch : visibleIDs.filter {
                        records[$0].map { $0.hiddenAt == nil && $0.describedAt != nil && !needsDescription($0) && $0.taggedRevision != tagRevision } == true
                    }
                    scanTotal = scanCompleted + Set(ids + batch).subtracting(scanAttemptedIDs).count
                    failed += await tagDescribedScreenshots(batch)
                    describedBatch.removeAll(keepingCapacity: true)
                    beginPhase(.describing)
                }
            }
            // Save descriptions independently; taxonomy/model failures must not lose them.
            if !Task.isCancelled, isActive, !userPaused, !storagePaused {
                do { try await persist() } catch { pauseForSaveError(error) }
            }
            if !Task.isCancelled, isActive, !userPaused, !storagePaused {
                do { try await discoverCategoriesIfNeeded() }
                catch is CancellationError { }
                catch {
                    if !Task.isCancelled { notice = "Category discovery couldn’t finish. Saved descriptions and text are kept. Resume to retry. \(error.localizedDescription)" }
                }
            }
            let taggingIDs = visibleIDs.filter { id in
                guard let record = records[id], record.hiddenAt == nil, record.scannedAt != nil else { return false }
                return record.describedAt != nil && !needsDescription(record) && record.taggedRevision != tagRevision
            }
            scanTotal = scanCompleted + Set(ids + taggingIDs).subtracting(scanAttemptedIDs).count
            tagTotal = tagCompleted + taggingIDs.count
            if !taggingIDs.isEmpty { beginPhase(.tagging) }
            failed += await tagDescribedScreenshots(taggingIDs)
        }
        if !Task.isCancelled, !userPaused, !storagePaused {
            for id in ids where !scanAttemptedIDs.contains(id) {
                if let record = records[id], record.scannedAt != nil,
                   !scanMeasurement.aiAvailable || record.taggedRevision == tagRevision { finishScreenshot(id) }
            }
        }
        await persistReportingError()
        // Cancellation means a refresh/restart/lifecycle handover owns what
        // happens next. Never end its allowance from the outgoing task.
        if storagePaused {
            // A storage failure owns the stop even when it cancelled this task;
            // unlike a refresh, it must end the background allowance.
            backgroundScan.finish(success: false)
        } else if !Task.isCancelled, scanCompleted == scanTotal || userPaused || persistenceFailed {
            backgroundScan.finish(success: scanCompleted == scanTotal && scanMeasurement.failed == 0 && !userPaused && !persistenceFailed && !storagePaused)
        }
        if failed > 0 && !Task.isCancelled && !persistenceFailed && notice == nil {
            notice = "\(failed) couldn’t be fully scanned. Search still includes any text already read. Use Rescan to retry."
        }
    }

    private func tagDescribedScreenshots(_ taggingIDs: [String]) async -> Int {
        tagTotal = tagCompleted + taggingIDs.count
        if !taggingIDs.isEmpty { beginPhase(.tagging) }
        var failed = 0
        for id in taggingIDs {
                if Task.isCancelled || !scanAllowed || !isActive || userPaused || storagePaused { break }
                guard let current = records[id], current.hiddenAt == nil else { continue }
                let revision = tagRevision
                do {
                    if tagger.unavailableReason == nil, current.taggedRevision != revision {
                        let suggestion: TagSuggestion
                        do {
                            let start = ProcessInfo.processInfo.systemUptime
                            defer { scanMeasurement.taggingSeconds += ProcessInfo.processInfo.systemUptime - start }
                            suggestion = tags.isEmpty ? TagSuggestion(title: current.title, tagIDs: [])
                                : try await tagger.tag(text: current.text, visualLabels: current.visualLabels, tags: tags,
                                                       description: current.contentDescription ?? "")
                        }
                        try Task.checkCancellation()
                        guard revision == tagRevision else { continue }
                        if var record = records[id] {
                            record.aiTagIDs = suggestion.tagIDs.intersection(allowedTagIDs)
                            record.taggedRevision = revision
                            record.lastError = nil
                            updateRecord(record)
                        }
                    }
                } catch is CancellationError {
                    break
                } catch {
                    if Task.isCancelled { break }
                    failed += 1
                    recordFailure(error, id: id)
                }
                aiMessage = tagger.unavailableReason
                tagCompleted += 1
                finishScreenshot(id)
                reportPhaseProgress()
                if !(await checkpointScanIfNeeded()) { break }
                await Task.yield()
            }
        return failed
    }

    private func needsDescription(_ record: Screenshot) -> Bool {
        record.describedAt == nil || record.contentDescription?.isEmpty != false ||
            (tagger.canDescribeImages && record.descriptionUsesImage != true)
    }

    private var describedCount: Int {
        visibleIDs.reduce(0) { count, id in
            count + (records[id].map { $0.hiddenAt == nil && $0.describedAt != nil && $0.contentDescription?.isEmpty == false } == true ? 1 : 0)
        }
    }

    private var categoryDiscoveryIsDue: Bool {
        guard tags.count < 32 else { return false }
        return TagRules.discoveryIsDue(count: describedCount, lastCount: categoryDiscoveryCount, completed: categoryDiscoveryCompleted)
    }

    private func discoverCategoriesIfNeeded() async throws {
        guard categoryDiscoveryIsDue, tags.count < 32 else { return }
        beginPhase(.discovering)
        let described = visibleIDs.compactMap { records[$0] }.filter { $0.hiddenAt == nil && $0.describedAt != nil }
        let retiring = !categoryDiscoveryCompleted
            ? TagRules.retireableDefaultIDs(tags: tags, records: Array(records.values)) : []
        let revision = tagRevision
        let names = try await tagger.discoverCategories(descriptions: TagRules.discoverySample(records: described),
                                                        existingTags: tags.filter { !retiring.contains($0.id) })
        try Task.checkCancellation()
        guard revision == tagRevision, isActive, !userPaused, !storagePaused else { return }
        // Manual tag edits made while the model ran must protect their categories.
        if let updated = TagRules.discoveredTaxonomy(names: names, tags: tags, records: Array(records.values),
                                                     dismissed: dismissedCategoryNames, retireDefaults: !categoryDiscoveryCompleted) {
            let retired = !Set(tags).isSubset(of: updated)
            tags = updated
            tagRevision += 1
            // Old starter AI IDs are ignored by effectiveTags; remove them from
            // stored records too, preserving every manual addition/removal.
            if retired {
                for id in Array(records.keys) {
                    guard var record = records[id] else { continue }
                    TagRules.prune(&record, allowed: allowedTagIDs)
                    updateRecord(record)
                }
            }
        }
        if !names.isEmpty { categoryDiscoveryCompleted = true }
        categoryDiscoveryCount = described.count
        libraryRevision += 1
        do { try await persist() }
        catch { pauseForSaveError(error); throw error }
    }

    private func beginPhase(_ phase: ScanPhase) {
        finishPhaseTiming()
        scanPhase = phase
        phaseStartedUptime = ProcessInfo.processInfo.systemUptime
        reportPhaseProgress()
    }

    private func reportPhaseProgress() {
        backgroundScan.updateProgress(completed: scanPhaseCompleted, total: scanPhaseTotal, title: scanPhase.title)
    }

    private func finishPhaseTiming() {
        guard let started = phaseStartedUptime else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        if scanPhase == .indexing { indexElapsed += elapsed }
        else if scanPhase == .describing { descriptionElapsed += elapsed }
        else { tagElapsed += elapsed }
        phaseStartedUptime = nil
    }

    private func finishScreenshot(_ id: String) {
        guard scanAttemptedIDs.insert(id).inserted else { return }
        scanCompleted += 1
        scanMeasurement.completed += 1
    }

    private func recordFailure(_ error: Error, id: String) {
        scanMeasurement.failed += 1
        if var record = records[id] {
            record.lastError = error.localizedDescription
            updateRecord(record)
        }
        aiMessage = tagger.unavailableReason
    }

    private func pauseForSaveError(_ error: Error) {
        persistenceFailed = true
        notice = "Couldn’t save the index. Scanning paused. \(error.localizedDescription)"
        storagePaused = true
        scanTask?.cancel()
    }

    private func checkpointScanIfNeeded() async -> Bool {
        // Bound crash recovery without rewriting the full JSON every ten images.
        if (indexCompleted + descriptionCompleted + tagCompleted) % 100 == 0 || ProcessInfo.processInfo.systemUptime - lastCheckpointUptime >= 30 {
            do { try await persist() }
            catch { pauseForSaveError(error); return false }
        }
        return true
    }

    private func preparationTask(for id: String?) -> Task<PreparedScan, Error>? {
        guard let id, let record = records[id], record.scannedAt == nil, record.hiddenAt == nil,
              !Task.isCancelled, scanAllowed else { return nil }
        let networkAllowed = downloadFromICloud
        let photos = photos
        let analyzer = analyzer
        return Task {
            let imageStart = ProcessInfo.processInfo.systemUptime
            let data = try await photos.analysisData(id: id, networkAllowed: networkAllowed)
            let imageSeconds = ProcessInfo.processInfo.systemUptime - imageStart
            try Task.checkCancellation()
            let analysisStart = ProcessInfo.processInfo.systemUptime
            let content = try await analyzer.analyze(imageData: data)
            return PreparedScan(content: content, imageSeconds: imageSeconds,
                                analysisSeconds: ProcessInfo.processInfo.systemUptime - analysisStart)
        }
    }

    private func scheduleSave() {
        guard isReady else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await self?.persistReportingError()
        }
    }

    private func finishEmptyBackgroundScan() {
        guard backgroundScan.hasRequest else { return }
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            await self.persistReportingError()
            guard self.generation == token, !self.isScanning else { return }
            self.backgroundScan.finish(success: !self.persistenceFailed && !self.storagePaused &&
                                       !self.userPaused && self.scanMeasurement.failed == 0)
        }
    }

    private func persist() async throws {
        guard isReady else { return }
        saveSequence += 1
        let revision = libraryRevision
        guard revision > persistedRevision || persistenceFailed else { return }
        let sequence = saveSequence
        let snapshot = IndexSnapshot(version: 1, tagRevision: tagRevision, tags: tags, screenshots: Array(records.values),
                                     categoryDiscoveryCount: categoryDiscoveryCount, categoryDiscoveryCompleted: categoryDiscoveryCompleted,
                                     dismissedCategoryNames: dismissedCategoryNames)
        try await disk.save(snapshot, sequence: sequence)
        persistedRevision = max(persistedRevision, revision)
        lastCheckpointUptime = ProcessInfo.processInfo.systemUptime
        if sequence == saveSequence { persistenceFailed = false }
    }

    private func persistReportingError() async {
        do { try await persist() }
        catch {
            persistenceFailed = true
            storagePaused = true
            scanTask?.cancel()
            notice = "Couldn’t save your changes. \(error.localizedDescription)"
        }
    }

    private struct IndexUnavailableError: LocalizedError {
        var errorDescription: String? { "Open your saved index before editing tags." }
    }
    private struct TagLimitError: LocalizedError {
        var errorDescription: String? { "Keep up to 32 tags. Rename or remove a tag to make room." }
    }
    private struct CachedSearch {
        let revision: Int
        let document: PreparedSearchDocument
    }
    private final class LibraryResultCache {
        var revision: Int
        let query: String
        let terms: [String]
        let filter: TagFilter
        let showingHidden: Bool
        var items: [Screenshot]
        let positions: [String: Int]
        var days: [ScreenshotDay]?
        private var dayPositions: [String: (day: Int, item: Int)] = [:]

        init(revision: Int, query: String, terms: [String], filter: TagFilter, showingHidden: Bool, items: [Screenshot]) {
            self.revision = revision
            self.query = query
            self.terms = terms
            self.filter = filter
            self.showingHidden = showingHidden
            self.items = items
            positions = Dictionary(items.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        }

        func cacheDays(_ groups: [ScreenshotDay]) {
            days = groups
            dayPositions = [:]
            for (dayIndex, day) in groups.enumerated() {
                for (itemIndex, item) in day.screenshots.enumerated() {
                    dayPositions[item.id] = (dayIndex, itemIndex)
                }
            }
        }

        func replace(_ record: Screenshot, at position: Int) {
            items[position] = record
            if let location = dayPositions[record.id], let day = days?[location.day] {
                var screenshots = day.screenshots
                screenshots[location.item] = record
                days?[location.day] = ScreenshotDay(id: day.id, screenshots: screenshots)
            }
        }
    }
    private struct PreparedScan: Sendable {
        let content: RecognizedContent
        let imageSeconds: TimeInterval
        let analysisSeconds: TimeInterval
    }
}
