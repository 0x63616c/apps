import RDesign
import SwiftUI

enum Palette {
    static let accent = RPalette.graphite
    static let clash = RPalette.graphite
    static let live = RPalette.graphite
}

struct AmbientBackground: View {
    var body: some View { RPalette.background.ignoresSafeArea() }
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
