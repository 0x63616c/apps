import StoreKit
import SwiftUI

/// Optional tips: consumables that unlock nothing. The Settings row only appears once every
/// product has loaded, so a missing or misconfigured store simply hides it.
@MainActor @Observable final class TipJar {
    enum Tip: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var productID: String { "com.calumwebb.still.tip.\(rawValue)" }
        var fallbackName: String {
            switch self { case .small: "Coffee"; case .medium: "Croissant"; case .large: "Gift" }
        }
        var symbol: String {
            switch self { case .small: "cup.and.saucer.fill"; case .medium: "fork.knife"; case .large: "gift.fill" }
        }
        init?(productID: String) {
            guard let tip = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
            self = tip
        }
    }
    enum Phase { case loading, ready, unavailable }

    static let shared = TipJar()
    private(set) var phase = Phase.loading
    private(set) var products: [Tip: Product] = [:]
    private(set) var purchasing: Tip?
    /// A calm, one-line status for pending or failed purchases. Cancelling says nothing.
    var notice: String?
    /// Set when a purchase completes; the sheet closes and Settings shows the thank-you.
    var completed: Tip?
    private var updates: Task<Void, Never>?

    func load() async {
        listenForUpdates()
        guard phase != .ready else { return }
        phase = .loading
        do {
            let loaded = try await Product.products(for: Tip.allCases.map(\.productID))
            products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in Tip(productID: product.id).map { ($0, product) } })
            phase = products.count == Tip.allCases.count ? .ready : .unavailable
        } catch {
            phase = .unavailable
        }
    }

    func buy(_ tip: Tip) async {
        guard let product = products[tip], purchasing == nil else { return }
        purchasing = tip
        notice = nil
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                completed = tip
            case .success(.unverified(let transaction, _)):
                await transaction.finish()
                notice = "The App Store couldn't verify that tip. If you were charged, Apple can refund it from your purchase history."
            case .pending:
                notice = "Your tip is waiting for approval. Thank you for the thought."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            notice = "That tip didn't go through. Please try again later."
        }
    }

    /// Ask to Buy approvals and interrupted purchases arrive later. Finish them quietly: no pop-ups.
    private func listenForUpdates() {
        guard updates == nil else { return }
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
            }
        }
    }
}

/// The App Store icon's mark on its near-black tile, which reads in light and dark.
struct TendrMark: View {
    var size: CGFloat = 72
    var body: some View {
        Image("LaunchGlyph").resizable().scaledToFit()
            .padding(size * 0.16)
            .frame(width: size, height: size)
            .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct TipJarSheet: View {
    @Environment(\.dismiss) private var dismiss
    let jar: TipJar
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    TendrMark().padding(.top, 8)
                    VStack(spacing: 8) {
                        Text("Support Tendr").font(.title.bold())
                        Text("Enjoying Tendr? Leave a tip.").foregroundStyle(.secondary)
                    }
                    VStack(spacing: 12) {
                        ForEach(TipJar.Tip.allCases) { tip in row(tip) }
                    }
                    if let notice = jar.notice {
                        Text(notice).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .accessibilityIdentifier("tipNotice")
                    }
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(jar.purchasing != nil) } }
        }
        .interactiveDismissDisabled(jar.purchasing != nil)
        .onChange(of: jar.completed) { _, tip in if tip != nil { dismiss() } }
        .onAppear { jar.notice = nil }
    }

    private func row(_ tip: TipJar.Tip) -> some View {
        let product = jar.products[tip]
        return HStack(spacing: 14) {
            Image(systemName: tip.symbol).font(.title3).foregroundStyle(Theme.pine)
                .frame(width: 44, height: 44).background(Theme.sage, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(product?.displayName ?? tip.fallbackName).font(.headline)
            Spacer(minLength: 8)
            Button { Task { await jar.buy(tip) } } label: {
                ZStack {
                    Text(product?.displayPrice ?? "").opacity(jar.purchasing == tip ? 0 : 1)
                    if jar.purchasing == tip { ProgressView().controlSize(.small).tint(Theme.background) }
                }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.background).frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .disabled(product == nil || jar.purchasing != nil)
            .accessibilityLabel("\(product?.displayName ?? tip.fallbackName), \(product?.displayPrice ?? "")")
            .accessibilityIdentifier("tip-\(tip.rawValue)")
        }.card()
    }
}

struct TipThanks: View {
    @Environment(\.dismiss) private var dismiss
    let tip: TipJar.Tip
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                TendrMark(size: 88)
                Text("Thank you").font(.largeTitle.bold()).accessibilityIdentifier("tipThanks")
                Button { dismiss() } label: { Text("Close").font(.headline).foregroundStyle(Theme.background).frame(maxWidth: 240).padding(.vertical, 6) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).padding(.top, 8)
            }.padding(32)
            ConfettiCannon().ignoresSafeArea().allowsHitTesting(false)
        }
    }
}

/// Two cannons in the bottom corners fire a single burst of monochrome paper that drifts down and fades.
struct ConfettiCannon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var start = Date()
    private let pieces = ConfettiPiece.burst(count: 170)
    private let duration = 4.6
    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(paused: Date().timeIntervalSince(start) > duration)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSince(start)
                    let shades: [Color] = scheme == .dark
                        ? [.white, Color(white: 0.82), Color(white: 0.62), Color(white: 0.44)]
                        : [Color(white: 0.06), Color(white: 0.28), Color(white: 0.46), Color(white: 0.66)]
                    for piece in pieces { piece.draw(in: context, size: size, time: time, shades: shades) }
                }
            }
            .accessibilityHidden(true)
        }
    }
}

struct ConfettiPiece {
    enum Shape { case rectangle, circle, ribbon }
    let fromLeft: Bool
    let angle: Double
    let speed: Double
    let delay: Double
    let spin: Double
    let flutter: Double
    let shade: Int
    let shape: Shape

    func draw(in context: GraphicsContext, size: CGSize, time: Double, shades: [Color]) {
        let t = time - delay
        guard t > 0 else { return }
        let drag = 1.25
        let travel = (1 - exp(-drag * t)) / drag
        let x = (fromLeft ? 0 : size.width) + (fromLeft ? 1 : -1) * cos(angle) * speed * travel
        let y = size.height + 10 - sin(angle) * speed * travel + 260 * t * t
        let opacity = max(0, min(1, (4.4 - t) / 0.9))
        guard opacity > 0, y < size.height + 40 else { return }
        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: x, y: y)
        layer.rotate(by: .radians(spin * t))
        layer.scaleBy(x: cos(flutter * t), y: 1)
        let path: Path = switch shape {
        case .rectangle: Path(CGRect(x: -4, y: -7, width: 8, height: 14))
        case .circle: Path(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8))
        case .ribbon: Path(roundedRect: CGRect(x: -2, y: -9, width: 4, height: 18), cornerRadius: 2)
        }
        layer.fill(path, with: .color(shades[shade % shades.count]))
    }

    /// Deterministic, so every celebration (and screenshot) looks the same.
    static func burst(count: Int) -> [ConfettiPiece] {
        var state: UInt64 = 0x7E4D_C0FF_EE00
        func random() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
        return (0..<count).map { index in
            ConfettiPiece(
                fromLeft: index.isMultiple(of: 2),
                angle: (52 + random() * 28) * .pi / 180,
                speed: 1350 + random() * 900,
                delay: random() * 0.22,
                spin: (random() - 0.5) * 14,
                flutter: 3 + random() * 7,
                shade: Int(random() * 4),
                shape: [.rectangle, .rectangle, .circle, .ribbon][Int(random() * 4)]
            )
        }
    }
}
