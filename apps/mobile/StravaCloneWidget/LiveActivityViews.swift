import SwiftUI
import WidgetKit

typealias LiveActivityState = RecordingActivityAttributes.ContentState

/// Lock screen (ADR-031 §9): the running Recording, or "Enregistrement interrompu" once stale,
/// or the final content after Save.
struct LiveActivityLockScreen: View {
    let attributes: RecordingActivityAttributes
    let state: LiveActivityState
    let isStale: Bool

    var body: some View {
        Group {
            if state.isSaved {
                SavedContent(attributes: attributes, state: state)
            } else if isStale {
                StaleContent(attributes: attributes, state: state)
            } else {
                RunningLockScreen(attributes: attributes, state: state)
            }
        }
        .foregroundStyle(.white)
    }
}

/// Sport, Time / Distance / Average pace or Speed, then the Itinerary line.
private struct RunningLockScreen: View {
    let attributes: RecordingActivityAttributes
    let state: LiveActivityState

    var body: some View {
        let stat = LiveActivitySportStat(attributes: attributes, state: state)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: attributes.sportSymbol).foregroundStyle(LiveActivityFormat.accent)
                Text(attributes.sportName).font(.caption.bold())
                Spacer()
                if state.isPaused { PausePill() }
            }
            HStack(alignment: .top) {
                column("Temps") { LiveActivityTimer(state: state) }
                column("Distance") { Text("\(LiveActivityFormat.kilometers(state.distanceM)) km") }
                column(stat.label) { Text("\(stat.value) \(stat.unit)") }
            }
            if let itinerary = state.itinerary {
                HStack(spacing: 8) {
                    Text(itinerary.state.caption)
                        .font(.caption2)
                        .foregroundStyle(itinerary.state == .offTrack ? LiveActivityFormat.pause : .white.opacity(0.7))
                    Text(LiveActivityFormat.remainingText(itinerary)).font(.caption.bold().monospacedDigit())
                    ProgressView(value: itinerary.fraction).tint(LiveActivityFormat.accent)
                }
            }
        }
    }

    private func column(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
            value().font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Expanded island, top: the Itinerary first (distance left or its state, then a bar with the
/// athlete's position), the distance large without one.
struct ExpandedIslandCenter: View {
    let attributes: RecordingActivityAttributes
    let state: LiveActivityState

    var body: some View {
        if let itinerary = state.itinerary {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(LiveActivityFormat.remainingText(itinerary)).font(.title.bold().monospacedDigit())
                    Text(itinerary.state == .onTrack ? "restants" : itinerary.state.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ItineraryTrackBar(
                    fraction: itinerary.fraction,
                    symbol: attributes.sportSymbol,
                    dimmed: itinerary.state == .offTrack || itinerary.state == .returnPath
                )
            }
            .padding(.horizontal, 12)
        } else {
            Text("\(LiveActivityFormat.kilometers(state.distanceM)) km").font(.title.bold().monospacedDigit())
        }
    }
}

/// Expanded island, bottom: timer, distance (with an Itinerary), pace or speed.
struct ExpandedIslandBottom: View {
    let attributes: RecordingActivityAttributes
    let state: LiveActivityState

    var body: some View {
        let stat = LiveActivitySportStat(attributes: attributes, state: state)
        HStack {
            LiveActivityTimer(state: state).frame(maxWidth: 80, alignment: .leading)
            Spacer()
            if state.itinerary != nil {
                Text("\(LiveActivityFormat.kilometers(state.distanceM)) km")
                Spacer()
            }
            Text("\(stat.value) \(stat.unit)")
            if state.isPaused { PausePill() }
        }
        .font(.callout.monospacedDigit())
        // Keeps the timer and the unit clear of the island's rounded corners.
        .padding(.horizontal, 12)
    }
}

/// Time minus Pauses, ticking on its own, frozen in a Pause.
struct LiveActivityTimer: View {
    let state: LiveActivityState

    var body: some View {
        Text(
            timerInterval: state.timerStart...Date.distantFuture,
            pauseTime: state.pausedAt,
            countsDown: false,
            showsHours: true
        )
        .monospacedDigit()
    }
}

private struct PausePill: View {
    var body: some View {
        Text("EN PAUSE")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(LiveActivityFormat.pause))
            .foregroundStyle(.black)
    }
}

/// Start-to-finish bar with the sport icon at the athlete's position, greyed off the track.
private struct ItineraryTrackBar: View {
    let fraction: Double
    let symbol: String
    let dimmed: Bool

    var body: some View {
        GeometryReader { geometry in
            let x = max(10, min(geometry.size.width - 10, geometry.size.width * fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 6)
                Capsule().fill(dimmed ? Color.gray : LiveActivityFormat.accent).frame(width: x, height: 6)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(dimmed ? Color.gray : .white))
                    .position(x: x, y: 10)
                Image(systemName: "flag.checkered")
                    .font(.caption2)
                    .position(x: geometry.size.width - 6, y: -4)
            }
        }
        .frame(height: 20)
    }
}

/// No update for 2 min: the app was killed or stopped.
private struct StaleContent: View {
    let attributes: RecordingActivityAttributes
    let state: LiveActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Enregistrement interrompu").font(.headline)
            }
            Text("\(attributes.sportName) · \(LiveActivityFormat.kilometers(state.distanceM)) km au dernier point")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Text("Ouvre l'app pour reprendre ta Recording.").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// After Save, until iOS removes it.
private struct SavedContent: View {
    let attributes: RecordingActivityAttributes
    let state: LiveActivityState

    var body: some View {
        let stat = LiveActivitySportStat(attributes: attributes, state: state, average: true)
        let seconds = Int((state.pausedAt ?? state.timerStart).timeIntervalSince(state.timerStart))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(attributes.sportName) enregistrée").font(.headline)
            }
            Text(
                "\(LiveActivityFormat.duration(max(0, seconds))) · \(LiveActivityFormat.kilometers(state.distanceM)) km · \(stat.value) \(stat.unit)"
            )
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            Text("Envoi en cours, elle apparaîtra dans ton flux.").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
