import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LockTestWidgetBundle: WidgetBundle {
    var body: some Widget { LockTestLiveActivity() }
}

struct LockTestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LockTestAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    LockScreenView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            } compactTrailing: {
                ChronoText(state: context.state).frame(width: 56)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            }
        }
    }
}

struct ChronoText: View {
    let state: LockTestAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.timerStart...Date.distantFuture, pauseTime: state.pausedAt, countsDown: false)
            .monospacedDigit()
    }
}

struct LockScreenView: View {
    let state: LockTestAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ChronoText(state: state).font(.title2.bold())
                Spacer()
                Text(state.isPaused ? "EN PAUSE" : "EN COURS")
                    .font(.caption.bold())
                    .foregroundStyle(state.isPaused ? .orange : .green)
            }
            HStack(spacing: 12) {
                Button(intent: TogglePauseIntent()) {
                    Label("A (\(state.openTaps))", systemImage: "playpause.fill")
                }
                .tint(.orange)
                Button(intent: AuthTogglePauseIntent()) {
                    Label("B auth (\(state.authTaps))", systemImage: "lock.fill")
                }
                .tint(.blue)
            }
            Text(state.lastRun).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .foregroundStyle(.white)
    }
}
