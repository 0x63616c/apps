"""Build an isolated, synthetic-data UI capture copy. Production source stays untouched."""
from pathlib import Path
import shutil
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--destination", type=Path, default=Path("/private/tmp/shotr-supported-source"))
parser.add_argument("--large-library", action="store_true", help="Default to 15,000 synthetic records. The generated app also accepts --large-library at launch.")
args = parser.parse_args()

root = Path(__file__).resolve().parents[1]
dest = args.destination
if dest.exists():
    raise SystemExit(f'{dest} already exists; inspect it before regenerating')
shutil.copytree(root, dest, ignore=shutil.ignore_patterns('.build', '.git', '.release', 'release', 'scripts', 'captures'))

# Keep the fixture self-contained while using the same shared UI package.
shutil.copytree(root.parents[1] / 'packages/RDesign', dest / 'RDesign',
                ignore=shutil.ignore_patterns('.build', '.swiftpm'))

def edit(path, before, after):
    file = dest / path
    source = file.read_text()
    assert before in source, (path, before)
    file.write_text(source.replace(before, after, 1))

edit('Shotr/LibraryStore.swift', 'guard !isReady, !isStarting else { return }', '''guard !isReady, !isStarting else { return }
        if !ProcessInfo.processInfo.arguments.contains("--test-refresh-scan") {
        lastScan = nil
        tags = IndexSnapshot.defaultTags
        let samples = CaptureSamples.records
        records = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
        visibleIDs = samples.map(\\.id)
        permission = .authorized
        isReady = true
        isLoading = false
        userPaused = true
        return ()
        }
        ''')
edit('Shotr/LibraryStore.swift', 'try await disk.load() ?? IndexSnapshot()',
     'IndexSnapshot(tags: IndexSnapshot.defaultTags, screenshots: CaptureSamples.records)')
edit('Shotr/LibraryStore.swift', 'guard isReady, isActive else { return }', '''if !ProcessInfo.processInfo.arguments.contains("--test-refresh-scan") {
            return // Only the refresh regression fixture runs the real reconciliation path.
        }
        guard isReady, isActive else { return }''')
edit('Shotr/LibraryStore.swift', 'private func persist() async throws {', 'private func persist() async throws {\n        return // Capture data never writes a Photos index.')
edit('Shotr/Views/LibraryView.swift', '.tint(Color.primary)\n    }', '''.tint(Color.primary)
        .task {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--header-transitions") {
                store.appearance = args.contains("--header-dark") ? .dark : .light
            }
            if !args.contains("--preserve-layout") { layout = .continuous }
            if args.contains("--capture-search") { query = "weekend"; searching = true }
            if args.contains("--capture-gallery") { openedID = "sample-0" }
            if args.contains("--capture-gallery-last") { openedID = "sample-\\(CaptureSamples.count - 1)" }
            assert(TagIcon.all.allSatisfy { UIImage(systemName: $0.id) != nil }, "Icon catalog contains unavailable SF Symbols")
            if args.contains("--capture-tags") { sheet = .tags }
            if args.contains("--capture-grouped") { layout = .byDay }
            if args.contains("--benchmark-scan") || args.contains("--test-scan") {
                await store.start()
                store.rescan()
                for _ in 0..<2400 {
                    if let measurement = store.lastScan {
                        let data = try? JSONEncoder().encode(measurement)
                        try? data?.write(to: URL.documentsDirectory.appendingPathComponent("scan-benchmark.json"))
                        let analysis = IndexSnapshot(tags: store.tags, screenshots: store.items)
                        let analysisData = try? JSONEncoder().encode(analysis)
                        try? analysisData?.write(to: URL.documentsDirectory.appendingPathComponent("scan-analysis.json"))
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }''')

# Synthetic source screenshots. These are fixture contents, never app-screen mockups.
with (dest/'Shotr/Services/PhotosClient.swift').open('a') as file:
    file.write('''
@MainActor private enum CaptureSamples {
    static let entries: [(String, String, String, String, Int)] = [
        ("FIELD NOTES", "A quieter\\nweekend", "Small places, good coffee, and a little time outside.", "sun.horizon", 2),
        ("STUDIO", "Objects for\\nevery day", "The everyday chair\\nNatural oak · woven seat\\n$240", "chair.lounge", 0),
        ("KITCHEN NOTES", "Lemon &\\nolive oil", "A simple weekend cake\\n45 minutes · serves six", "birthday.cake", 1),
        ("MESSAGES", "Saturday plans", "Let's take the coast road.\\n\\nCoffee at nine?\\n\\nPerfect. See you there.", "bubble.left.and.bubble.right", 5),
        ("WEEKEND GUIDE", "Along the\\ncoast", "A slow weekend in Northern California.\\nThree stops worth making.", "water.waves", 2),
        ("READING LIST", "Make room\\nfor ideas", "On attention, creative work, and the value of an empty afternoon.", "book.closed", 9),
        ("LIVE MUSIC", "After\\nhours", "SATURDAY  ·  8 PM\\nThe listening room\\nDoors at 7:30", "waveform", 4),
        ("COFFEE CLUB", "The perfect\\npour", "18g coffee · 300g water\\nMedium grind\\nBrew slowly, enjoy.", "cup.and.saucer", 1),
        ("TRAIL NOTES", "Take the\\nlong way", "Coastal loop\\n6.2 miles · easy pace\\nBring a layer.", "mountain.2", 3),
        ("ORDER CONFIRMED", "Thank you.", "Notebook — charcoal\\nQuantity 2\\nSubtotal  $28.00\\nDelivery  $0.00", "checkmark.seal", 8),
        ("WORK NOTES", "Less, but\\nbetter", "Make the important thing obvious.\\nRemove one step.\\nLeave room to breathe.", "square.stack.3d.up", 6),
        ("SAVE FOR LATER", "A different\\nperspective", "Collected thoughts on spaces, objects, and the places between.", "sparkle", 7),
        ("WEEKEND WALKS", "Out of\\noffice", "A weekend without a schedule.\\nStart at the water.", "figure.walk", 2),
        ("DESIGN JOURNAL", "In good\\nshape", "A collection of useful objects.\\nDesigned to last.", "circle.lefthalf.filled", 7),
        ("ON THE MENU", "Sunday\\nsupper", "Roasted vegetables\\nFresh bread\\nSomething sweet", "fork.knife", 1),
    ]
    static let defaultCount = 15
    static var count: Int {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--test-scan") { return 6 }
        if arguments.contains("--large-library") { return 15_000 }
        return defaultCount
    }
    static var records: [Screenshot] {
        let scannedAt = Date()
        let fixtureDate = Date(timeIntervalSince1970: 1790442000)
        // Keep the first large day long in every simulator time zone.
        let newest = count > entries.count ? Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: fixtureDate)! : fixtureDate
        return (0..<count).map { index in
            let item = entries[index % entries.count]
            let title = item.1.replacingOccurrences(of: "\\n", with: " ") + (index < entries.count ? "" : " #\\(index)")
            // Large days allow scrolling within one section to verify pinning.
            let interval = count > entries.count ? 60 : 7200
            let transitionGroups = [4, 1, 7, 2, 1]
            var group = 0
            var remaining = index
            for size in transitionGroups {
                if remaining < size { break }
                remaining -= size
                group += 1
            }
            let createdAt = ProcessInfo.processInfo.arguments.contains("--header-transitions")
                ? Calendar.current.date(byAdding: .day, value: -group, to: newest)!
                : newest.addingTimeInterval(-Double(index * interval))
            return Screenshot(id: "sample-\\(index)", createdAt: createdAt,
                        title: title, text: item.0 + " " + item.2,
                        visualLabels: ["poster", "text"],
                        contentDescription: index == 1 ? nil : "A designed poster titled \\(title). " + item.2.replacingOccurrences(of: "\\n", with: " "),
                        describedAt: index == 1 ? nil : scannedAt,
                        descriptionUsesImage: index == 1 ? nil : false,
                        addedTagIDs: [IndexSnapshot.defaultTags[item.4].id], scannedAt: scannedAt, taggedRevision: 1)
        }
    }
    // Cache by design, not asset ID: even 15,000 records retain at most 15 images.
    private static var images: [Int: UIImage] = [:]
    static func image(id: String) -> UIImage? {
        guard id.hasPrefix("sample-"), let recordIndex = Int(id.dropFirst(7)), (0..<count).contains(recordIndex) else { return nil }
        let index = recordIndex % entries.count
        if let image = images[index] { return image }
        let item = entries[index]
        let colors: [UIColor] = [
            UIColor(red: 0.83, green: 0.87, blue: 0.79, alpha: 1),
            UIColor(red: 0.89, green: 0.84, blue: 0.75, alpha: 1),
            UIColor(red: 0.95, green: 0.88, blue: 0.65, alpha: 1),
            UIColor(red: 0.84, green: 0.88, blue: 0.92, alpha: 1),
            UIColor(red: 0.65, green: 0.78, blue: 0.82, alpha: 1)
        ]
        let dark = index == 6 || index == 11
        let background = dark ? UIColor(white: 0.10, alpha: 1) : colors[index % colors.count]
        let foreground = dark ? UIColor.white : UIColor(white: 0.12, alpha: 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 1000), format: format).image { context in
            background.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 1000))
            func text(_ value: String, _ y: CGFloat, _ size: CGFloat, _ weight: UIFont.Weight) {
                (value as NSString).draw(in: CGRect(x: 42, y: y, width: 516, height: 240), withAttributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: foreground
                ])
            }
            text("9:41", 22, 20, .semibold)
            text(item.0, 110, 19, .semibold)
            let line = UIBezierPath(); line.move(to: CGPoint(x: 42, y: 152)); line.addLine(to: CGPoint(x: 558, y: 152))
            foreground.withAlphaComponent(0.25).setStroke(); line.stroke()
            text(item.1, 202, 67, .bold)
            if let symbol = UIImage(systemName: item.3, withConfiguration: UIImage.SymbolConfiguration(pointSize: 130, weight: .ultraLight)) {
                symbol.withTintColor(foreground.withAlphaComponent(0.70), renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(x: 215, y: 435, width: 170, height: 150))
            }
            text(item.2, 648, 27, .regular)
            text("SAMPLE SCREENSHOT", 936, 15, .medium)
        }
        images[index] = image
        return image
    }
}
''')
# The store needs the fixture type; internal scope keeps it shared only within the capture target.
p = dest/'Shotr/Services/PhotosClient.swift'
p.write_text(p.read_text().replace('@MainActor private enum CaptureSamples', '@MainActor enum CaptureSamples'))
print(dest)

# Fully disconnect the fixture build from the system Photos library.
p = dest/'Shotr/Services/PhotosClient.swift'
source = p.read_text()
p.write_text('''import Photos
import UIKit
enum PhotosClientError: Error { case missingAsset, imageUnavailable }
@MainActor final class PhotosClient {
    var onChange: (() -> Void)?
    private(set) var libraryChangeRevision: UInt64 = 0
    private let encoder = CaptureImageEncoder()
    init() {
        if ProcessInfo.processInfo.arguments.contains("--test-refresh-scan") {
            Task { [weak self] in
                // More frequent than an image analysis, but outside the store's
                // debounce interval: reproduce iCloud/thumbnail change storms.
                for _ in 0..<240 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self else { return }
                    self.libraryChangeRevision &+= 1
                    self.onChange?()
                }
            }
        }
    }
    var authorization: PHAuthorizationStatus { .authorized }
    func requestAccess() async -> PHAuthorizationStatus { .authorized }
    func fetchScreenshots() async -> [PhotoItem] {
        CaptureSamples.records.map { PhotoItem(id: $0.id, createdAt: $0.createdAt, modifiedAt: $0.modifiedAt) }
    }
    func image(id: String, targetSize: CGSize, networkAllowed: Bool) async throws -> UIImage {
        try Task.checkCancellation()
        guard let image = CaptureSamples.image(id: id) else { throw PhotosClientError.missingAsset }
        // Full-size designs are shared; grid/filmstrip requests get small bitmaps.
        let scale = min(1, min(max(1, targetSize.width) / image.size.width,
                               max(1, targetSize.height) / image.size.height))
        guard scale < 1 else { return image }
        let size = CGSize(width: max(1, floor(image.size.width * scale)),
                          height: max(1, floor(image.size.height * scale)))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    func analysisData(id: String, networkAllowed: Bool) async throws -> Data {
        if ProcessInfo.processInfo.arguments.contains("--test-scan") {
            try await Task.sleep(for: .milliseconds(700))
        }
        let image = try await image(id: id, targetSize: CGSize(width: 1600, height: 2400), networkAllowed: networkAllowed)
        try Task.checkCancellation()
        return try await encoder.encode(image)
    }
    func delete(ids: Set<String>) async throws { throw PhotosClientError.missingAsset }
    func presentLimitedLibraryPicker() {}
}
private actor CaptureImageEncoder {
    func encode(_ image: UIImage) throws -> Data {
        try Task.checkCancellation()
        guard let data = image.jpegData(compressionQuality: 0.92) else { throw PhotosClientError.imageUnavailable }
        return data
    }
}
''' + source[source.index('@MainActor enum CaptureSamples'):])
if args.large_library:
    edit('Shotr/Services/PhotosClient.swift', 'static let defaultCount = 15', 'static let defaultCount = 15_000')
edit('Shotr/LibraryStore.swift', 'PHPhotoLibrary.authorizationStatus(for: .readWrite)', 'PHAuthorizationStatus.authorized')

edit("Shotr/Views/LibraryView.swift", "import Photos", "import UIKit\nimport Photos")

# Native-only transition controls: sample real collection layout offsets without
# relying on swipe inertia. Never included in the production app/project.
edit('Shotr/Views/LibraryView.swift', 'let view = UICollectionView(frame: .zero, collectionViewLayout: Self.layout',
     'let view = HeaderProbeCollectionView(frame: .zero, collectionViewLayout: Self.layout')
edit('Shotr/Views/LibraryView.swift', 'private final class DayGridLayout: UICollectionViewLayout {', '''private final class HeaderProbeCollectionView: UICollectionView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { collectionViewLayout.invalidateLayout(); setNeedsLayout() }
        }
    }

    private final class DayGridLayout: UICollectionViewLayout {''')
edit('Shotr/Views/LibraryView.swift', 'private var contentSizeCategory: UIContentSizeCategory?', '''private var contentSizeCategory: UIContentSizeCategory?
        private var probeIndex = -1
        private var probeButtons: [UIButton] = []

        private var probeOffsets: [CGFloat] {
            geometry.starts.dropFirst().flatMap { next -> [CGFloat] in
                let h = geometry.headerHeight
                return [next-h-1, next-h-1/3, next-h+0.001, next-h+1/3,
                        next-h/2, next-1, next-0.001, next+0.001, next+1/3, next+1]
            }.filter { $0 >= 0 }
        }
        private func installProbe(_ view: UICollectionView) {
            guard ProcessInfo.processInfo.arguments.contains("--header-transitions"),
                  let parent = view.window else { return }
            view.contentInset.bottom = 700
            if probeButtons.isEmpty {
                for (title, direction) in [("previousHeaderSample", -1), ("nextHeaderSample", 1)] {
                    let button = UIButton(type: .system)
                    button.setTitle(direction > 0 ? "Next" : "Back", for: .normal)
                    button.accessibilityIdentifier = title
                    button.tag = direction
                    button.backgroundColor = .systemBackground
                    button.addTarget(self, action: #selector(stepProbe(_:)), for: .touchUpInside)
                    parent.addSubview(button)
                    probeButtons.append(button)
                }
            }
            let visibleFrame = view.convert(view.bounds, to: parent)
            for (index, button) in probeButtons.enumerated() {
                button.frame = CGRect(x: visibleFrame.midX - 70 + CGFloat(index)*72,
                                      y: visibleFrame.maxY - 60, width: 68, height: 48)
            }
        }
        @objc private func stepProbe(_ sender: UIButton) {
            let offsets = probeOffsets
            guard !offsets.isEmpty, let view = collectionView else { return }
            probeIndex = min(max(0, probeIndex + sender.tag), offsets.count - 1)
            view.setContentOffset(CGPoint(x: 0, y: offsets[probeIndex]), animated: false)
            view.layoutIfNeeded()
        }''')
edit('Shotr/Views/LibraryView.swift', 'let top = view.bounds.minY + view.adjustedContentInset.top\n            if let section',
     'installProbe(view)\n            let top = view.bounds.minY + view.adjustedContentInset.top\n            if let section')
edit('Shotr/Views/LibraryView.swift', 'accessibilityValue = "offset=\\(top);',
     'accessibilityValue = "style=\\(view.traitCollection.userInterfaceStyle.rawValue); offset=\\(top);')
