import SwiftUI

/// In-app picture of the Lock Screen with the Live Activity, using the same view the widget extension renders.
struct LockScreenPreview: View {
    @Environment(\.dismiss) private var dismiss
    var festival: Festival
    var plan: LivePlan
    var now: Date

    var body: some View {
        let attributes = FestrActivityAttributes(
            festivalID: festival.id,
            festivalName: festival.name,
            day: plan.day.description,
            dayLabel: FestivalClock(festival).weekday(plan.day),
            timeZoneIdentifier: festival.timeZoneIdentifier
        )
        let state = previewState
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .bottom) {
                WallpaperCanvas(festival: festival, day: plan.day, sets: [], theme: .midnight, size: size)
                    .overlay(alignment: .top) {
                        LockClockOverlay(theme: .midnight, size: size, now: previewNow, timeZone: festival.timeZone)
                    }
                VStack(spacing: 14) {
                    LiveActivityLockScreenView(attributes: attributes, state: state, referenceDate: previewNow)
                        .environment(\.colorScheme, .dark)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.45), in: .rect(cornerRadius: 24))
                        .glassEffect(.clear, in: .rect(cornerRadius: 24))
                        .accessibilityIdentifier("liveActivityLockScreen")
                    Text("Preview. Your Live Activity looks like this on the Lock Screen.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 24) + 60)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding()
                .accessibilityIdentifier("closePreview")
        }
        .preferredColorScheme(.dark)
    }

    /// Off the festival day, show the moment the first set is playing so the preview isn't empty.
    private var previewNow: Date {
        if plan.content(at: now).current != nil || plan.content(at: now).next != nil, !plan.isOver(at: now) { return now }
        guard let first = plan.sets.first else { return now }
        return first.start.addingTimeInterval(min(first.effectiveEnd.timeIntervalSince(first.start) * 0.4, 45 * 60))
    }

    private var previewState: LiveActivityContent {
        plan.content(at: previewNow)
    }
}
