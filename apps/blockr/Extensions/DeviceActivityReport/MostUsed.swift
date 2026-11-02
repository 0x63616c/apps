import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

@main
struct MostUsedExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        MostUsedReport { apps in
            MostUsedView(apps: apps)
        }
    }
}

struct AppUsage: Identifiable {
    let token: ApplicationToken
    let duration: TimeInterval
    var id: ApplicationToken { token }
}

struct MostUsedReport: DeviceActivityReportScene {
    let context = DeviceActivityReport.Context("mostUsed")
    let content: ([AppUsage]) -> MostUsedView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [AppUsage] {
        var durations: [ApplicationToken: TimeInterval] = [:]
        for await activity in data {
            for await segment in activity.activitySegments {
                for await category in segment.categories {
                    for await app in category.applications {
                        guard let token = app.application.token,
                              app.totalActivityDuration.isFinite,
                              app.totalActivityDuration > 0 else { continue }
                        durations[token, default: 0] += app.totalActivityDuration
                    }
                }
            }
        }
        // Usage and opaque identities remain inside the report sandbox.
        return durations.map { AppUsage(token: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
            .prefix(8)
            .map { $0 }
    }
}

struct MostUsedView: View {
    let apps: [AppUsage]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if apps.isEmpty {
                    Text("No activity").foregroundStyle(.secondary)
                }
                ForEach(apps) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Label(app.token)
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(shortDuration(app.duration))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                        GeometryReader { geometry in
                            Capsule().fill(.white.opacity(0.15))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white)
                                        .frame(width: geometry.size.width * app.duration / max(apps.first?.duration ?? 1, 1))
                                }
                        }
                        .frame(height: 4)
                        .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 8)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }

    private func shortDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes == 0 { return "<1m" }
        let hours = minutes / 60
        if hours == 0 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
    }
}
