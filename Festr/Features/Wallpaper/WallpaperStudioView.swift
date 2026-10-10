import Photos
import SwiftUI
import UIKit

struct WallpaperStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @AppStorage("wallpaperTheme") private var theme: WallpaperTheme = .midnight
    @AppStorage("wallpaperContent") private var content: WallpaperContent = .mySets
    @State private var festivalID: String?
    @State private var day: LocalDate?
    @State private var status: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let festival = selectedFestival {
                        controls(festival)
                        preview(festival: festival, day: currentDay(festival))
                        Text(status ?? "Saved at your iPhone's full resolution. Set it from Photos › Share › Use as Wallpaper.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("wallpaperStatus")
                    } else {
                        ContentUnavailableView("No set times yet", systemImage: "iphone.gen3", description: Text("Wallpapers appear once a festival publishes set times."))
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) {
                if let festival = selectedFestival {
                    actions(festival: festival, day: currentDay(festival))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Wallpaper")
        }
    }

    private var festivals: [Festival] {
        let preferred = model.scheduleFestivals
        let others = model.upcomingFestivals.filter { $0.hasSetTimes && !preferred.contains($0) }
        return preferred + others
    }

    private var selectedFestival: Festival? {
        festivals.first { $0.id == festivalID } ?? festivals.first
    }

    private func currentDay(_ festival: Festival) -> LocalDate {
        if let day, festival.days.contains(day) { return day }
        return festival.festivalDay(at: model.now()) ?? festival.days.first ?? festival.startDate
    }

    private func sets(_ festival: Festival, _ day: LocalDate) -> [FestivalSet] {
        content == .mySets ? model.chosenSets(in: festival, on: day) : festival.sets(on: day)
    }

    private var screenSize: CGSize {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
        return screen?.bounds.size ?? CGSize(width: 402, height: 874)
    }

    private func controls(_ festival: Festival) -> some View {
        VStack(spacing: 12) {
            if festivals.count > 1 {
                Picker("Festival", selection: Binding(get: { festival.id }, set: { festivalID = $0; day = nil })) {
                    ForEach(festivals) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DayPicker(festival: festival, selection: Binding(get: { currentDay(festival) }, set: { day = $0 }))
            Picker("Content", selection: $content) {
                ForEach(WallpaperContent.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("wallpaperContent")
            HStack(spacing: 12) {
                ForEach(WallpaperTheme.allCases) { option in
                    Button {
                        withAnimation(.snappy) { theme = option }
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(option.background)
                                .frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme == option ? Palette.accent : .clear, lineWidth: 2.5))
                            Text(option.name).font(.caption.weight(theme == option ? .semibold : .regular))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("theme-\(option.rawValue)")
                    .accessibilityAddTraits(theme == option ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private func preview(festival: Festival, day: LocalDate) -> some View {
        let size = screenSize
        let width: CGFloat = 210
        let scale = width / size.width
        return WallpaperCanvas(festival: festival, day: day, sets: sets(festival, day), theme: theme, size: size)
            .overlay(alignment: .top) { LockClockOverlay(theme: theme, size: size, now: model.now(), timeZone: festival.timeZone) }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wallpaper preview")
            .accessibilityIdentifier("wallpaperPreview")
    }

    private func actions(festival: Festival, day: LocalDate) -> some View {
        GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        save(festival: festival, days: [day])
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("saveWallpaper")
                    Button {
                        save(festival: festival, days: festival.days)
                    } label: {
                        Label("Save all days", systemImage: "square.stack").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("saveAllWallpapers")
                }
                .controlSize(.large)
                .disabled(isSaving)
        }
    }

    private func save(festival: Festival, days: [LocalDate]) {
        let size = screenSize
        let images = days.compactMap { day in
            WallpaperRenderer.image(festival: festival, day: day, sets: sets(festival, day), theme: theme, size: size, scale: displayScale)
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await PhotoSaver.save(images)
                status = images.count == 1 ? "Saved to Photos." : "Saved \(images.count) wallpapers to Photos."
            } catch PhotoSaver.Failure.denied {
                status = "Festr can't add to Photos. Allow it in Settings › Privacy › Photos."
            } catch {
                status = "Couldn't save. Please try again."
            }
        }
    }
}

/// Sketch of the system clock so the preview shows the area the wallpaper keeps clear.
struct LockClockOverlay: View {
    var theme: WallpaperTheme
    var size: CGSize
    var now: Date
    var timeZone: TimeZone

    var body: some View {
        var dateStyle = Date.FormatStyle().weekday(.wide).month(.wide).day()
        dateStyle.timeZone = timeZone
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "h:mm"
        timeFormatter.timeZone = timeZone
        return VStack(spacing: 0) {
            Text(now.formatted(dateStyle))
                .font(.system(size: size.width * 0.05, weight: .semibold))
            Text(timeFormatter.string(from: now))
                .font(.system(size: size.width * 0.25, weight: .bold, design: .rounded))
        }
        .foregroundStyle(theme.primary.opacity(0.92))
        .padding(.top, size.height * 0.075)
    }
}

enum PhotoSaver {
    enum Failure: Error { case denied }

    /// Add-only access: Festr never reads the photo library.
    static func save(_ images: [UIImage]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            for image in images {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    }
}
