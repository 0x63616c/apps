import SwiftUI

enum Palette {
    static let accent = Color(red: 0.98, green: 0.36, blue: 0.42)
    static let clash = Color.orange
    static let live = Color(red: 0.25, green: 0.85, blue: 0.55)
}

/// Soft, slowly-shifting colour field behind every screen, so the glass has something to refract.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let points: [SIMD2<Float>] = [
        SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
        SIMD2(0, 0.5), SIMD2(0.6, 0.45), SIMD2(1, 0.5),
        SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
    ]

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    private static let darkColors: [Color] = [
        rgb(0.05, 0.05, 0.10), rgb(0.10, 0.06, 0.18), rgb(0.05, 0.06, 0.12),
        rgb(0.14, 0.06, 0.16), rgb(0.06, 0.05, 0.10), rgb(0.04, 0.09, 0.16),
        rgb(0.03, 0.03, 0.06), rgb(0.08, 0.04, 0.10), rgb(0.03, 0.04, 0.08)
    ]

    private static let lightColors: [Color] = [
        rgb(1.00, 0.95, 0.93), rgb(0.97, 0.94, 1.00), rgb(0.93, 0.96, 1.00),
        rgb(1.00, 0.92, 0.92), rgb(0.98, 0.97, 0.99), rgb(0.92, 0.95, 1.00),
        rgb(0.99, 0.97, 0.95), rgb(0.96, 0.94, 0.99), rgb(0.95, 0.97, 1.00)
    ]

    var body: some View {
        MeshGradient(width: 3, height: 3, points: Self.points, colors: colorScheme == .dark ? Self.darkColors : Self.lightColors)
            .ignoresSafeArea()
    }
}

extension View {
    /// A Liquid Glass card.
    func glassCard(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    func screenBackground() -> some View {
        background { AmbientBackground() }
    }
}

struct Pill: View {
    var text: String
    var systemImage: String?
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

extension FestivalClock {
    init(_ festival: Festival) {
        self.init(timeZone: festival.timeZone)
    }

    /// "Pacific Time", so it's clear times are local to the festival.
    func zoneName() -> String {
        timeZone.localizedName(for: .generic, locale: locale) ?? timeZone.identifier
    }
}
