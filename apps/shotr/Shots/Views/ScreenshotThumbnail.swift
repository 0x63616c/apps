import SwiftUI

struct ScreenshotThumbnail: View {
    let photos: PhotosClient
    let item: Screenshot
    let side: CGFloat
    let networkAllowed: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var unavailable = false

    private var requestID: String { "\(item.id)-\(item.modifiedAt?.timeIntervalSince1970 ?? 0)-\(Int(side * displayScale))-\(networkAllowed)" }

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if unavailable {
                Image(systemName: "icloud").foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side).clipped()
        .task(id: requestID) {
            image = nil; unavailable = false
            do {
                let loaded = try await photos.image(id: item.id, targetSize: CGSize(width: side * displayScale, height: side * displayScale * 2.2), networkAllowed: networkAllowed)
                try Task.checkCancellation()
                image = loaded
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { unavailable = true }
            }
        }
    }
}
