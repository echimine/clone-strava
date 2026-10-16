import SwiftUI

/// The end-of-Recording celebration (ADR-032 §5), over the finish screen: the trace draws
/// itself on `background`, the final stats count up, haptics mark the end of the draw and of the
/// count, and after `CelebrationTimeline.settlesAt` (or one tap) `onFinished` hands over to the
/// form. The timing is `CelebrationTimeline`'s; the background only draws a `CelebrationFrame`,
/// so the no-map sketch can be swapped for the Mapbox 3D map without touching this sequence.
struct RecordingCelebration<Background: View>: View {
    let stats: RecordingStats
    /// The background shrinks into the finish screen's view matched with
    /// `CelebrationGeometry.miniMapID` in this namespace: the mini-map.
    let namespace: Namespace.ID
    /// `skipped`: the athlete tapped to jump to the end state.
    let onFinished: (_ skipped: Bool) -> Void
    @ViewBuilder let background: (CelebrationFrame) -> Background

    @State private var start = Date.now
    @State private var isFinished = false

    var body: some View {
        TimelineView(.animation(paused: isFinished)) { context in
            let frame = CelebrationTimeline.frame(at: context.date.timeIntervalSince(start))
            ZStack(alignment: .bottom) {
                background(frame)
                    .ignoresSafeArea()
                    .matchedGeometryEffect(id: CelebrationGeometry.miniMapID, in: namespace)
                CelebrationStats(items: FinishStatsCountUp.items(stats, progress: frame.countProgress))
                    .padding(.horizontal, Theme.spacing)
                    .padding(.bottom, 48)
                    .transition(.opacity)
            }
            .sensoryFeedback(trigger: frame.milestone) { _, milestone in
                switch milestone {
                case .drawing: nil
                case .traceDrawn: .impact(weight: .medium)
                case .counted: .success
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish(skipped: true) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Touchez pour passer")
        .accessibilityIdentifier("recordingCelebration")
        .onAppear { start = .now }
        .task {
            try? await Task.sleep(for: .seconds(CelebrationTimeline.settlesAt))
            finish(skipped: false)
        }
    }

    private func finish(skipped: Bool) {
        guard !isFinished else { return }
        isFinished = true
        onFinished(skipped)
    }
}

/// The celebration's background and the finish screen's mini-map share one geometry: the
/// background shrinks into the mini-map's place when the form appears (ADR-032 §5, step 5).
enum CelebrationGeometry {
    static let miniMapID = "recordingCelebrationMiniMap"
}

/// The counting stats, white on the brand background.
private struct CelebrationStats: View {
    let items: [RecordingStatItem]

    var body: some View {
        HStack(alignment: .top) {
            ForEach(items) { item in
                VStack(spacing: 4) {
                    Text(item.value)
                        .font(.system(size: 34, weight: .heavy).italic())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.unit.isEmpty ? item.label : "\(item.label) (\(item.unit))")
                        .font(.caption.weight(.semibold))
                        .opacity(0.85)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
    }
}

/// The no-map celebration background (ADR-032 §5 fallback, offline at the end of an outing):
/// the trace draws itself in white on the plain brand orange. North is up, as on the mini-map.
struct CelebrationSketchBackground: View {
    let trace: [Coordinate]
    /// 0...1, the drawn share of the trace.
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack {
                Theme.accent
                // Proportional room for the stats below: the same layout once shrunk.
                PolylineSketch(coordinates: trace, inset: min(proxy.size.width, height) * 0.12)
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .padding(.top, height * 0.06)
                    .padding(.bottom, height * 0.2)
            }
        }
    }
}
