import Photos
import PhotosUI
import UIKit

enum PhotosClientError: LocalizedError {
    case missingAsset, needsDownload, imageUnavailable, timedOut

    var errorDescription: String? {
        switch self {
        case .missingAsset: return "This screenshot is no longer available."
        case .needsDownload: return "Enable iCloud downloads to scan this screenshot."
        case .imageUnavailable: return "This screenshot couldn't be loaded. Try again."
        case .timedOut: return "Loading took too long. Try again."
        }
    }
}

/// A request may call back synchronously, more than once, or after cancellation.
/// Keep the continuation and request ID under one lock; never resume while locked.
private final class ImageRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var result: Result<UIImage, Error>?
    private var requestID: PHImageRequestID?
    private var timeout: DispatchWorkItem?
    private let manager: PHImageManager

    init(manager: PHImageManager) { self.manager = manager }

    func attach(_ continuation: CheckedContinuation<UIImage, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setRequestID(_ id: PHImageRequestID) {
        lock.lock()
        requestID = id
        let finished = result != nil
        lock.unlock()
        if finished { manager.cancelImageRequest(id) }
    }

    func startTimeout() {
        let work = DispatchWorkItem { [weak self] in
            self?.finish(.failure(PhotosClientError.timedOut), cancelRequest: true)
        }
        lock.lock()
        let finished = result != nil
        if !finished { timeout = work }
        lock.unlock()
        if !finished { DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: work) }
    }

    func finish(_ result: Result<UIImage, Error>, cancelRequest: Bool = false) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let requestID = self.requestID
        let timeout = self.timeout
        self.timeout = nil
        lock.unlock()
        timeout?.cancel()
        if cancelRequest, let requestID { manager.cancelImageRequest(requestID) }
        continuation?.resume(with: result)
    }
}

@MainActor
final class PhotosClient: NSObject, PHPhotoLibraryChangeObserver {
    var onChange: (() -> Void)?
    private let manager = PHCachingImageManager()
    private let renderer = PhotoImageRenderer()
    nonisolated private let changeTracker = ScreenshotChangeTracker()

    var authorization: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Synchronous observer revision closes the gap between Photos' delivery
    /// queue and the corresponding MainActor onChange notification.
    var libraryChangeRevision: UInt64 { changeTracker.changeRevision }

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Filter on Photos' delivery queue, before spawning a MainActor task. An
        // image/iCloud callback usually changes no relevant screenshot metadata.
        guard changeTracker.consume(changeInstance) else { return }
        Task { @MainActor [weak self] in self?.onChange?() }
    }

    func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func fetchScreenshots() async -> [PhotoItem] {
        guard authorization == .authorized || authorization == .limited else { return [] }
        // Enumerating thousands of PHAssets is synchronous. Do not make scrolling
        // wait for a foreground refresh; only lightweight Sendable values return.
        let tracker = changeTracker
        return await Task.detached(priority: .userInitiated) {
            tracker.fetch()
        }.value
    }

    func image(id: String, targetSize: CGSize, networkAllowed: Bool) async throws -> UIImage {
        try Task.checkCancellation()
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              asset.mediaSubtypes.contains(.photoScreenshot) else { throw PhotosClientError.missingAsset }
        let size = CGSize(width: max(1, min(targetSize.width, 4096)),
                          height: max(1, min(targetSize.height, 4096)))
        let state = ImageRequestState(manager: manager)
        let image: UIImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard state.attach(continuation) else { return }
                let options = PHImageRequestOptions()
                options.version = .current
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.isNetworkAccessAllowed = networkAllowed
                options.isSynchronous = false
                options.progressHandler = { _, error, _, _ in
                    if let error { state.finish(.failure(error), cancelRequest: true) }
                }
                state.startTimeout()
                let requestID = manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                     options: options) { image, info in
                    if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true {
                        state.finish(.failure(CancellationError()))
                    } else if !networkAllowed,
                              (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue == true,
                              image == nil || (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true {
                        state.finish(.failure(PhotosClientError.needsDownload), cancelRequest: true)
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else if (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true {
                        // Ignore temporary thumbnails; the final response or timeout completes the request.
                    } else if let image {
                        state.finish(.success(image))
                    } else {
                        state.finish(.failure(PhotosClientError.imageUnavailable))
                    }
                }
                state.setRequestID(requestID)
            }
        } onCancel: {
            state.finish(.failure(CancellationError()), cancelRequest: true)
        }
        try Task.checkCancellation()
        guard image.size.width > 0, image.size.height > 0 else { throw PhotosClientError.imageUnavailable }
        let resized = try await renderer.resize(image, to: size)
        try Task.checkCancellation()
        return resized
    }

    func analysisData(id: String, networkAllowed: Bool) async throws -> Data {
        let image = try await image(id: id, targetSize: CGSize(width: 1600, height: 2400), networkAllowed: networkAllowed)
        try Task.checkCancellation()
        return try await renderer.encode(image)
    }

    func delete(ids: Set<String>) async throws {
        guard !ids.isEmpty else { return }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var screenshots: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { screenshots.append(asset) }
        }
        guard !screenshots.isEmpty else { throw PhotosClientError.missingAsset }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(screenshots as NSArray)
        }
    }

    func presentLimitedLibraryPicker() {
        guard authorization == .limited,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = controller.presentedViewController { controller = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}

/// PHFetchResult and its metadata are accessed only under this lock. Full
/// enumeration occurs on an actual refresh; ordinary change callbacks inspect
/// only changed objects, not all 15,000 screenshots.
private final class ScreenshotChangeTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var result: PHFetchResult<PHAsset>?
    private var metadata: [String: PhotoItem] = [:]
    private var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private var revision: UInt64 = 0

    var changeRevision: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }

    func fetch() -> [PhotoItem] {
        lock.lock()
        defer { lock.unlock() }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var items: [PhotoItem] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in items.append(Self.item(asset)) }
        // Photos does not promise a stable order for equal creation dates.
        items.sort { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt > rhs.createdAt
        }
        result = assets
        metadata = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return items
    }

    func consume(_ change: PHChange) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let relevant = consumeLocked(change)
        if relevant { revision &+= 1 }
        return relevant
    }

    private func consumeLocked(_ change: PHChange) -> Bool {
        let currentAuthorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        var relevant = currentAuthorization != authorization
        authorization = currentAuthorization
        guard let result else { return true }
        guard let details = change.changeDetails(for: result) else { return relevant }
        self.result = details.fetchResultAfterChanges
        guard details.hasIncrementalChanges else { return true }
        relevant = relevant || !(details.insertedIndexes?.isEmpty ?? true) ||
            !(details.removedIndexes?.isEmpty ?? true) || details.hasMoves
        for asset in details.changedObjects {
            let item = Self.item(asset)
            if metadata[item.id] != item { relevant = true }
            metadata[item.id] = item
        }
        for asset in details.insertedObjects { metadata[asset.localIdentifier] = Self.item(asset) }
        for asset in details.removedObjects { metadata.removeValue(forKey: asset.localIdentifier) }
        return relevant
    }

    private static func item(_ asset: PHAsset) -> PhotoItem {
        PhotoItem(id: asset.localIdentifier, createdAt: asset.creationDate ?? .distantPast,
                  modifiedAt: asset.modificationDate)
    }
}

/// Resizing and JPEG compression must not stall scrolling on the main actor.
private actor PhotoImageRenderer {
    func resize(_ image: UIImage, to size: CGSize) throws -> UIImage {
        try Task.checkCancellation()
        // Photos normally honors the requested pixel size. Avoid decoding and
        // redrawing every grid thumbnail when no orientation/size fix is needed.
        if image.imageOrientation == .up, let pixels = image.cgImage,
           CGFloat(pixels.width) <= size.width, CGFloat(pixels.height) <= size.height {
            return image
        }
        // UIKit applies the Photos orientation when drawing. A scale of one also
        // guarantees that both display and OCR receive bounded pixel dimensions.
        let scale = min(1, min(size.width / image.size.width, size.height / image.size.height))
        let outputSize = CGSize(width: max(1, floor(image.size.width * scale)),
                                height: max(1, floor(image.size.height * scale)))
        return autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: outputSize))
            }
        }
    }

    func encode(_ image: UIImage) throws -> Data {
        try Task.checkCancellation()
        let encoded = autoreleasepool { image.jpegData(compressionQuality: 0.92) }
        guard let data = encoded else { throw PhotosClientError.imageUnavailable }
        return data
    }
}
