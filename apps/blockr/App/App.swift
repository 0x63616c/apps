import SwiftUI
import BlockrCore
#if os(iOS)
import UIKit
import UserNotifications
#endif

@main struct BlockrApp: App {
    @StateObject private var model = Model()
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PushDelegate.self) var delegate
    #endif
    var body: some Scene {
        #if os(macOS)
        WindowGroup("Blockr", id: "main") { RootView().environmentObject(model).preferredColorScheme(.dark).tint(.white) }
            .defaultSize(width: 1000, height: 720)
        MenuBarExtra("Blockr", systemImage: model.locked ? "lock.fill" : "lock.shield") {
            VStack(alignment: .leading, spacing: 20) {
                Text("Blockr").font(.title2.weight(.semibold))
                if let lock = model.live.last {
                    Text(lock.group.name).font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Durations.clock(lock.end.timeIntervalSince(model.timerDate(context.date)), remaining: true))
                            .font(.system(size: 58, weight: .medium)).monospacedDigit()
                    }
                    ElapsedLockTime(start: lock.start).environmentObject(model)
                    Text("\(model.state.receipts.first(where: { $0.lockID == lock.id })?.coverage == .active ? "Active" : model.state.receipts.first(where: { $0.lockID == lock.id })?.coverage == .partial ? "Websites only" : "Not protected on this Mac") · until \(lock.end.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                } else { Text("Nothing locked").foregroundStyle(.secondary) }
                OpenWindowButton(title: model.locked ? "Open Blockr" : "Start a lock")
            }.padding(24).frame(width: 340).background(.black).preferredColorScheme(.dark).tint(.white)
        }.menuBarExtraStyle(.window)
        #else
        WindowGroup { RootView().environmentObject(model).preferredColorScheme(.dark).tint(.white) }
        #endif
    }
}
#if os(macOS)
private struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    var title: String
    var body: some View {
        Button(title) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .init("BlockrShowLock"), object: nil)
        }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
    }
}
#endif
#if os(iOS)
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if Bundle.main.object(forInfoDictionaryKey: "BlockrCloudEnabled") as? String == "YES" { application.registerForRemoteNotifications() }
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            let model = Model(startMaintenance: false)
            let before = model.state.replica
            await model.synchronize()
            if case .error = model.syncStatus { completionHandler(.failed) }
            else { completionHandler(model.state.replica == before ? .noData : .newData) }
        }
    }
}
#endif
