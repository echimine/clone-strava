// PROTOTYPE — throwaway (wayfinder #43, ticket #53). Never merged.
// The real Live Activity: renders the variant named by `ContentState.variant`, so the app switches it live.

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RecordingWidgetBundle: WidgetBundle {
    var body: some Widget { RecordingLiveActivity() }
}

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenContent(sport: context.attributes.sport, s: context.state, isStale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Parts.lockTint(context.state).opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let sport = context.attributes.sport
            let v = s.variant
            let inactive = context.isStale || s.ending != nil
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if !inactive { Parts.expandedLeading(v, sport, s) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !inactive { Parts.expandedTrailing(v, sport, s) }
                }
                DynamicIslandExpandedRegion(.center) {
                    if !inactive { Parts.expandedCenter(v, sport, s) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if inactive {
                        LockScreenContent(sport: sport, s: s, isStale: context.isStale)
                    } else {
                        Parts.expandedBottom(v, sport, s)
                    }
                }
            } compactLeading: {
                if inactive {
                    Image(systemName: sport.symbol).foregroundStyle(.gray)
                } else {
                    Parts.compactLeading(v, sport, s)
                }
            } compactTrailing: {
                if inactive {
                    Image(systemName: s.ending != nil ? "checkmark" : "exclamationmark.triangle").foregroundStyle(.gray)
                } else {
                    Parts.compactTrailing(v, sport, s)
                }
            } minimal: {
                if inactive {
                    Image(systemName: sport.symbol).foregroundStyle(.gray)
                } else {
                    Parts.minimal(v, sport, s)
                }
            }
        }
    }
}
