import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FestrWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FestrLiveActivity()
    }
}

struct FestrLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FestrActivityAttributes.self) { context in
            LiveActivityLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(LiveStyle.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.current == nil ? "UP NEXT" : "NOW")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(context.state.current == nil ? LiveStyle.accent : LiveStyle.live)
                        Text((context.state.current ?? context.state.next)?.artist ?? "Done for today")
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let current = context.state.current {
                        Text(current.isOpenEnded ? "late" : LiveStyle.time(current.end, zone: context.attributes.timeZoneIdentifier))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                    } else if let next = context.state.next {
                        Text(LiveStyle.time(next.start, zone: context.attributes.timeZoneIdentifier))
                            .font(.subheadline.monospacedDigit())
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let current = context.state.current {
                            SetProgress(slot: current)
                            Text(current.stage).font(.caption).foregroundStyle(.secondary)
                        }
                        if let next = context.state.next, context.state.current != nil {
                            HStack {
                                Text("Next").font(.caption.weight(.semibold)).foregroundStyle(LiveStyle.accent)
                                Text(next.artist).font(.caption).lineLimit(1)
                                Spacer()
                                Text(LiveStyle.time(next.start, zone: context.attributes.timeZoneIdentifier))
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(LiveStyle.accent)
            } compactTrailing: {
                LiveActivityCompactTrailing(state: context.state)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(LiveStyle.accent)
            }
            .keylineTint(LiveStyle.accent)
        }
    }
}
