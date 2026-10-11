import SwiftUI

@main
struct FestrApp: App {
    @State private var model = AppModel()
    @State private var live = LiveActivityController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(live)
                .tint(Palette.accent)
        }
    }
}

enum AppTab: Hashable {
    case discover, schedule, wallpaper, stopwatch
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LiveActivityController.self) private var live
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .discover

    var body: some View {
        TabView(selection: $tab) {
            Tab("Discover", systemImage: "sparkles", value: AppTab.discover) {
                DiscoverView()
            }
            Tab("My Schedule", systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }
            Tab("Wallpaper", systemImage: "iphone.gen3", value: AppTab.wallpaper) {
                WallpaperStudioView()
            }
            Tab("Stopwatch", systemImage: "stopwatch", value: AppTab.stopwatch) {
                StopwatchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await model.refresh()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            live.restore()
            // Local updates while the app runs; the timer-based views keep progress moving in between.
            while !Task.isCancelled {
                live.tick(model: model)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
