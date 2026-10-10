import SwiftUI

enum WallpaperTheme: String, CaseIterable, Identifiable {
    case midnight, sunset, paper

    var id: String { rawValue }

    var name: String {
        switch self {
        case .midnight: "Midnight"
        case .sunset: "Sunset"
        case .paper: "Paper"
        }
    }

    var background: LinearGradient {
        switch self {
        case .midnight:
            LinearGradient(colors: [Color(red: 0.04, green: 0.04, blue: 0.09), Color(red: 0.12, green: 0.07, blue: 0.24), Color(red: 0.03, green: 0.03, blue: 0.07)], startPoint: .top, endPoint: .bottom)
        case .sunset:
            LinearGradient(colors: [Color(red: 0.98, green: 0.52, blue: 0.36), Color(red: 0.72, green: 0.15, blue: 0.47), Color(red: 0.20, green: 0.06, blue: 0.33)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paper:
            LinearGradient(colors: [Color(red: 0.97, green: 0.95, blue: 0.91), Color(red: 0.91, green: 0.88, blue: 0.82)], startPoint: .top, endPoint: .bottom)
        }
    }

    var glow: Color {
        switch self {
        case .midnight: Color(red: 0.55, green: 0.35, blue: 1.0).opacity(0.35)
        case .sunset: Color(red: 1.0, green: 0.85, blue: 0.55).opacity(0.35)
        case .paper: Color(red: 0.92, green: 0.55, blue: 0.42).opacity(0.18)
        }
    }

    var primary: Color { self == .paper ? Color(red: 0.12, green: 0.11, blue: 0.10) : .white }
    var secondary: Color { primary.opacity(self == .paper ? 0.55 : 0.68) }
    var accent: Color {
        switch self {
        case .midnight: Color(red: 0.98, green: 0.45, blue: 0.55)
        case .sunset: Color(red: 1.0, green: 0.88, blue: 0.62)
        case .paper: Color(red: 0.80, green: 0.33, blue: 0.24)
        }
    }
}

enum WallpaperContent: String, CaseIterable, Identifiable {
    case mySets, fullLineup
    var id: String { rawValue }
    var name: String { self == .mySets ? "My sets" : "Full lineup" }
}

/// A lock-screen wallpaper for one festival day, laid out in points for `size` (the screen size).
/// The top third stays empty so the clock and widgets sit on clean background.
struct WallpaperCanvas: View {
    var festival: Festival
    var day: LocalDate
    var sets: [FestivalSet]
    var theme: WallpaperTheme
    var size: CGSize

    var body: some View {
        let clock = FestivalClock(festival)
        let scale = rowScale
        ZStack(alignment: .topLeading) {
            theme.background
            Circle()
                .fill(theme.glow)
                .frame(width: size.width * 1.1)
                .blur(radius: size.width * 0.25)
                .offset(x: size.width * 0.35, y: size.height * 0.55)

            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: size.height * 0.36)

                Text(festival.name.uppercased())
                    .font(.system(size: 13 * scale.header, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(theme.accent)
                Text(clock.weekday(day))
                    .font(.system(size: 34 * scale.header, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primary)
                    .padding(.top, 2)
                Text("\(clock.monthDay(day)) · \(festival.city)")
                    .font(.system(size: 14 * scale.header, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .padding(.bottom, 18 * scale.row)

                VStack(alignment: .leading, spacing: 11 * scale.row) {
                    ForEach(sets) { set in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(clock.time(set.start))
                                .font(.system(size: 15 * scale.row, weight: .semibold).monospacedDigit())
                                .foregroundStyle(theme.accent)
                                .frame(width: 78 * scale.row, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(set.artist)
                                    .font(.system(size: 17 * scale.row, weight: .semibold))
                                    .foregroundStyle(theme.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                if showsStages {
                                    Text(festival.stageName(for: set))
                                        .font(.system(size: 12 * scale.row, weight: .regular))
                                        .foregroundStyle(theme.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    if sets.isEmpty {
                        Text("No sets picked for this day")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(theme.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, size.width * 0.09)
            .padding(.bottom, size.height * 0.14)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var showsStages: Bool { festival.stages.count > 1 }

    /// Shrinks rows so long lineups still fit between the clock area and the bottom controls.
    private var rowScale: (header: CGFloat, row: CGFloat) {
        let widthScale = size.width / 402
        let available = size.height * 0.50 - 90 * widthScale
        let perRow: CGFloat = (showsStages ? 46 : 31) * widthScale
        let needed = perRow * CGFloat(max(sets.count, 1))
        let fit = min(1, available / needed)
        return (widthScale, widthScale * max(0.55, fit))
    }
}

/// Renders wallpapers at the device's native pixel size.
@MainActor
enum WallpaperRenderer {
    static func image(festival: Festival, day: LocalDate, sets: [FestivalSet], theme: WallpaperTheme, size: CGSize, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: WallpaperCanvas(festival: festival, day: day, sets: sets, theme: theme, size: size)
            .environment(\.colorScheme, theme == .paper ? .light : .dark))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
