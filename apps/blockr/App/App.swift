import SwiftUI
import BlockrCore
#if os(iOS)
import UIKit
#endif

@main struct BlockrApp: App {
    @StateObject private var model = Model()
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PushDelegate.self) var delegate
    #endif
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model).preferredColorScheme(.dark).tint(.white) }
        #if os(macOS)
        .defaultSize(width: 1000, height: 720)
        MenuBarExtra("Blockr", systemImage: model.locked ? "lock.fill" : "lock.shield") {
            VStack(alignment: .leading, spacing: 20) {
                Text("Blockr").font(.title2.weight(.semibold))
                if let lock = model.live.last {
                    Text(lock.group.name).font(.headline)
                    Text(lock.end, style: .timer).font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("\(model.state.receipts.first(where: { $0.lockID == lock.id })?.coverage == .active ? "Active" : "Not protected on this Mac") · until \(lock.end.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                } else { Text("Nothing locked").foregroundStyle(.secondary) }
                OpenWindowButton()
            }.padding(24).frame(width: 340).background(.black)
        }.menuBarExtraStyle(.window)
        #endif
    }
}
#if os(macOS)
private struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    var body: some View { Button("Open Blockr") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }.buttonStyle(.borderedProminent) }
}
#endif
#if os(iOS)
final class PushDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.object(forInfoDictionaryKey: "BlockrCloudEnabled") as? String == "YES" { application.registerForRemoteNotifications() }
        return true
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            let model = Model()
            await model.synchronize()
            completionHandler(.newData)
        }
    }
}
#endif
