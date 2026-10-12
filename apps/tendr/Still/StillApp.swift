import RDesign
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
    static let pine = RPalette.graphite
    static let background = RPalette.background
    static let card = RPalette.card
    static var sage: Color { pine.opacity(0.10) }
    /// Weight and Health: graphite, so the app stays black, white and graphite whatever accent is chosen.
    static let weight = RPalette.graphite
}
func number(_ value: Double, digits: Int = 1) -> String { value.formatted(.number.precision(.fractionLength(0...digits))) }

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
