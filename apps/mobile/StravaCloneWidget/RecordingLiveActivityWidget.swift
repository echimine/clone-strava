import ActivityKit
import SwiftUI
import WidgetKit

@main
struct StravaCloneWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivityWidget()
    }
}

/// The Live Activity of a Recording (ADR-031 §9): lock screen like Strava, compact island with
/// distance and timer, minimal island with the sport, expanded island Itinerary first. No
/// buttons: tapping opens the app. Stale once the app stops updating it (killed app), final
/// content after Save.
struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LiveActivityLockScreen(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            let inactive = context.isStale || state.isSaved
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    if !inactive {
                        ExpandedIslandCenter(attributes: attributes, state: state)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if inactive {
                        LiveActivityLockScreen(attributes: attributes, state: state, isStale: context.isStale)
                    } else {
                        ExpandedIslandBottom(attributes: attributes, state: state)
                    }
                }
            } compactLeading: {
                if inactive {
                    Image(systemName: attributes.sportSymbol).foregroundStyle(.gray)
                } else {
                    Text("\(LiveActivityFormat.kilometersShort(state.distanceM)) km")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(state.isPaused ? LiveActivityFormat.pause : LiveActivityFormat.accent)
                }
            } compactTrailing: {
                if inactive {
                    Image(systemName: state.isSaved ? "checkmark" : "exclamationmark.triangle").foregroundStyle(.gray)
                } else {
                    LiveActivityTimer(state: state)
                        .frame(maxWidth: 56)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(state.isPaused ? LiveActivityFormat.pause : .white)
                }
            } minimal: {
                Image(systemName: !inactive && state.isPaused ? "pause.fill" : attributes.sportSymbol)
                    .foregroundStyle(
                        inactive ? .gray : state.isPaused ? LiveActivityFormat.pause : LiveActivityFormat.accent
                    )
            }
        }
    }
}
