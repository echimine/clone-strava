import SwiftUI

/// The Recording in progress (ADR-031 §8): stats view by default, map view one tap away,
/// a large Pause button while moving, Resume and Finish (with confirmation) in a Pause.
struct RecordingLiveView: View {
    let store: RecordingStore
    let snapshot: RecordingSnapshot

    @Environment(LocationPermissionService.self) private var permission
    @State private var showsMap = false
    @State private var confirmsFinish = false

    private var isPaused: Bool { snapshot.recording.isPaused }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let stats = snapshot.stats(at: context.date)
            ZStack {
                if showsMap {
                    RecordingLiveMap(trace: snapshot.trace)
                        .overlay(alignment: .top) { compactBanner(stats).padding(.top, 8) }
                } else {
                    statsPage(stats)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .animation(.snappy, value: snapshot.recording.phase)
        .confirmationDialog(RecordingMessages.finishTitle, isPresented: $confirmsFinish, titleVisibility: .visible) {
            Button("Terminer") { Task { await store.finish() } }
        } message: {
            Text(RecordingMessages.finishMessage)
        }
    }

    private var gpsIndicator: GPSIndicator {
        GPSIndicator(position: snapshot.position, isAccuracyReduced: permission.isAccuracyReduced)
    }

    // MARK: Stats view

    private func statsPage(_ stats: RecordingStats) -> some View {
        let items = RecordingFormatters.items(stats)
        return VStack(spacing: 0) {
            header
            if isPaused {
                Text(RecordingMessages.paused.uppercased())
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.recordingPause)
                    .foregroundStyle(.black)
                    .padding(.top, 12)
                    .accessibilityIdentifier("recordingPausedBanner")
            }
            if let message = store.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red).padding(.top, 8)
            }
            Spacer()
            bigStat(items[0], size: 60)
            Divider().padding(.horizontal, 40).padding(.vertical, 18)
            bigStat(items[1], size: 88)
            Divider().padding(.horizontal, 40).padding(.vertical, 18)
            HStack {
                ForEach(items.dropFirst(2)) { bigStat($0, size: 44).frame(maxWidth: .infinity) }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(isPaused ? Color.recordingPause.opacity(0.12) : Color(.systemBackground))
    }

    private var header: some View {
        HStack {
            Label(
                RecordingFormatters.sportLabel(snapshot.recording.sport),
                systemImage: RecordingFormatters.sportSymbol(snapshot.recording.sport)
            )
            .font(.subheadline.weight(.semibold))
            Spacer()
            RecordingGPSChip(indicator: gpsIndicator)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func bigStat(_ item: RecordingStatItem, size: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(item.value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(item.unit.isEmpty ? item.label : "\(item.label) (\(item.unit))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recordingStat.\(item.label)")
    }

    // MARK: Map view

    private func compactBanner(_ stats: RecordingStats) -> some View {
        HStack(spacing: 18) {
            ForEach(RecordingFormatters.items(stats).prefix(3)) { item in
                VStack(spacing: 0) {
                    Text(item.value).font(.title3.weight(.bold)).monospacedDigit()
                    Text(item.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassBackground(in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottom) {
            if isPaused {
                Text(RecordingMessages.paused.uppercased())
                    .font(.caption.weight(.bold))
                    .padding(6)
                    .background(Color.recordingPause, in: Capsule())
                    .foregroundStyle(.black)
                    .offset(y: 26)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 20) {
            circleButton(showsMap ? "chart.bar.fill" : "map.fill", label: showsMap ? "Vue stats" : "Vue carte") {
                showsMap.toggle()
            }
            if isPaused {
                capsuleButton("Reprendre", fill: Theme.accent, identifier: "recordingResumeButton") {
                    Task { await store.resume() }
                }
                capsuleButton("Terminer", fill: .black, identifier: "recordingFinishButton") {
                    confirmsFinish = true
                }
            } else {
                Button {
                    Task { await store.pause() }
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Theme.accent, in: Circle())
                }
                .accessibilityLabel("Pause")
                .accessibilityIdentifier("recordingPauseButton")
                // Keeps the Pause button centered.
                Color.clear.frame(width: 56, height: 56)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 56, height: 56)
                .glassBackground(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("recordingViewToggle")
    }

    private func capsuleButton(_ title: String, fill: Color, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 130, height: 60)
                .background(fill, in: Capsule())
        }
        .accessibilityIdentifier(identifier)
    }
}
