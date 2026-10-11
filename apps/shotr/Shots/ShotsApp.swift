import SwiftUI
import UIKit

@MainActor
final class ShotsAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundScanCoordinator.shared.register()
        return true
    }
}

@main
struct ShotsApp: App {
    @UIApplicationDelegateAdaptor(ShotsAppDelegate.self) private var appDelegate
    @State private var store = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView(store: store)
                .preferredColorScheme(colorScheme)
                .task { await store.start() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: Task { await store.sceneChanged(active: true) }
                    case .background: Task { await store.sceneChanged(active: false) }
                    case .inactive: break // Control Center/system sheets are not backgrounding.
                    @unknown default: break
                    }
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
