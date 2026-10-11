import SwiftUI

@main struct StillApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup { RootView().environment(store).tint(Theme.pine).modifier(MedicalDisclaimerGate()) }
    }
}

/// Compile-time switches for features held back from the 1.0 App Store release.
enum FeatureFlags {
    /// Syringe-unit and mL dose entry (units → mg conversion). Off for 1.0: doses are logged in mg only.
    /// Stored `syringeUnits` data is still decoded and kept; it is simply not shown or edited.
    static let syringeUnits = false
    /// The "coming soon" assistant preview. Off until the assistant is real.
    static let assistantPreview = false
}

@MainActor enum Theme {
    static let preferences = AccentPreferences()
    static var pine: Color { preferences.color }
    static let background = Color(light: UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1), dark: UIColor.black)
    static let card = Color(light: .white, dark: UIColor(white: 0.065, alpha: 1))
    static var sage: Color { pine.opacity(0.10) }
    /// Weight and Health: graphite, so the app stays black, white and graphite whatever accent is chosen.
    static let weight = Color(light: UIColor(white: 0.28, alpha: 1), dark: UIColor(white: 0.72, alpha: 1))
}
extension Color {
    init(light: UIColor, dark: UIColor) { self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light }) }
}
extension View {
    func card() -> some View { padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.035), lineWidth: 1)) }
}
struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) { self.title = title; self.trailing = trailing() }
    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("pageHeader-\(title)")
            Spacer()
            // Taller trailing controls (Progress uses a 52 pt add button) lay out at 44 pt and
            // overflow evenly, so every page title sits at the same position.
            trailing.frame(maxHeight: 44)
        }.frame(minHeight: 44)
    }
}
extension PageHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}
func number(_ value: Double, digits: Int = 1) -> String { value.formatted(.number.precision(.fractionLength(0...digits))) }

struct FilterBar<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(Value, String)]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons
            ScrollView(.horizontal, showsIndicators: false) { buttons }
        }
    }
    private var buttons: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title).font(.subheadline.weight(.semibold)).fixedSize()
                        .padding(.horizontal, 15).frame(minHeight: 44)
                        .foregroundStyle(selection == value ? Theme.background : Color.primary)
                        .background(selection == value ? Theme.pine : Theme.card, in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}

@MainActor @Observable final class AccentPreferences {
    var selection: String = UserDefaults.standard.string(forKey: "accentColor") ?? "Graphite" {
        didSet { UserDefaults.standard.set(selection, forKey: "accentColor") }
    }
    let options = ["Graphite", "Orange", "Purple", "Blue", "Teal", "Rose"]
    var color: Color {
        switch selection {
        case "Orange": Color(light: UIColor(red: 0.65, green: 0.27, blue: 0.02, alpha: 1), dark: .systemOrange)
        case "Purple": Color(light: UIColor(red: 0.37, green: 0.32, blue: 0.83, alpha: 1), dark: UIColor(red: 0.69, green: 0.65, blue: 1, alpha: 1))
        case "Blue": Color(light: .systemBlue, dark: .systemCyan)
        case "Teal": Color(light: UIColor(red: 0.02, green: 0.46, blue: 0.43, alpha: 1), dark: UIColor(red: 0.39, green: 0.84, blue: 0.73, alpha: 1))
        case "Rose": Color(light: .systemPink, dark: UIColor(red: 1, green: 0.55, blue: 0.65, alpha: 1))
        default: Color(light: UIColor(white: 0.28, alpha: 1), dark: UIColor(white: 0.72, alpha: 1))
        }
    }
}

/// Shows a one-time "journal, not medical advice" notice on first launch.
struct MedicalDisclaimerGate: ViewModifier {
    @AppStorage("acknowledgedMedicalDisclaimer") private var acknowledged = false
    private var skip: Bool { ProcessInfo.processInfo.arguments.contains("--uitest") || ProcessInfo.processInfo.arguments.contains("--demo") }
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { !acknowledged && !skip }, set: { if !$0 { acknowledged = true } })) {
            MedicalDisclaimerView { acknowledged = true }.interactiveDismissDisabled()
        }
    }
}
struct MedicalDisclaimerView: View {
    var onContinue: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 12)
            Image(systemName: "book.closed.fill").font(.system(size: 34, weight: .medium)).foregroundStyle(Theme.pine)
                .frame(width: 72, height: 72).background(Theme.sage, in: RoundedRectangle(cornerRadius: 22))
            Text("A journal, not medical advice").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("Tendr helps you record doses and weight. It does not tell you what or how much to take.", systemImage: "pencil.and.list.clipboard")
                Label("Medication graphs are simplified estimates, not measured levels.", systemImage: "chart.xyaxis.line")
                Label("Always follow your prescriber's instructions and talk to them before changing a dose.", systemImage: "stethoscope")
                Label("Your journal stays on this iPhone. No account, no servers.", systemImage: "lock.shield")
            }.font(.body).foregroundStyle(.secondary)
            Spacer()
            Button(action: onContinue) { Text("I understand").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("acknowledgeDisclaimer")
        }.padding(28).background(Theme.background.ignoresSafeArea())
    }
}
