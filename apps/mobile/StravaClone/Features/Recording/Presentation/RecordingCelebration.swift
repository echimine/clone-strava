import SwiftUI

/// The end-of-Recording celebration (ADR-032 §5), over the finish screen: the trace draws
/// itself on `background`, the final stats count up, haptics mark the end of the draw and of the
/// count, and after `CelebrationTimeline.settlesAt` (or one tap) `phase` moves on: the
/// background shrinks into the mini-map while the form appears, then the celebration is over.
/// The timing is `CelebrationTimeline`'s; the background only draws a `CelebrationFrame`, so the
/// no-map sketch can be swapped for the Mapbox 3D map without touching this sequence.
struct RecordingCelebration<Background: View>: View {
    let stats: RecordingStats
    /// The background shrinks into the finish screen's view matched with
    /// `CelebrationGeometry.miniMapID` in this namespace: the mini-map.
    let namespace: Namespace.ID
    @Binding var phase: CelebrationPhase
    @ViewBuilder let background: (CelebrationFrame) -> Background

    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation(paused: phase != .playing)) { context in
            let frame = CelebrationTimeline.frame(at: context.date.timeIntervalSince(start))
            ZStack(alignment: .bottom) {
                // Still on screen while it shrinks, so the map keeps drawing every frame of it.
                background(frame)
                    .ignoresSafeArea()
                    .matchedGeometryEffect(id: CelebrationGeometry.miniMapID, in: namespace, isSource: phase == .playing)
                CelebrationStats(items: FinishStatsCountUp.items(stats, progress: frame.countProgress))
                    .padding(.horizontal, Theme.spacing)
                    .padding(.bottom, 48)
                    .opacity(phase == .playing ? 1 : 0)
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
        // The form is usable as soon as it appears.
        .allowsHitTesting(phase == .playing)
        .onAppear { start = .now }
        .task {
            try? await Task.sleep(for: .seconds(CelebrationTimeline.settlesAt))
            finish(skipped: false)
        }
    }

    /// `skipped`: the athlete tapped to jump to the end state.
    private func finish(skipped: Bool) {
        guard phase == .playing else { return }
        withAnimation(CelebrationMiniMap.settleAnimation(skipped: skipped)) {
            phase = .settling
        } completion: {
            // The map now looks like the mini-map under it; a short fade covers the no-map sketch.
            withAnimation(.easeOut(duration: 0.2)) { phase = .over }
        }
    }
}

/// Where the celebration stands on the finish screen (ADR-032 §5): playing over the hidden
/// form, shrinking into the mini-map while the form appears, then gone.
enum CelebrationPhase: Equatable {
    case playing, settling, over
}

/// The celebration's background and the finish screen's mini-map share one geometry: the
/// background shrinks into the mini-map's place when the form appears (ADR-032 §5, step 5).
enum CelebrationGeometry {
    static let miniMapID = "recordingCelebrationMiniMap"
}

/// The finish screen's mini-map, where the celebration's background lands (ADR-032 §5, step 5).
/// It loads during the celebration, hidden with the form, so the background shrinks into a map
/// already drawn rather than one reloading (#83); it joins the celebration's geometry only at
/// the end.
struct CelebrationMiniMap: View {
    let trace: [Coordinate]
    let namespace: Namespace.ID
    let isCelebrating: Bool

    static let height: CGFloat = 200
    static let cornerRadius: CGFloat = 16

    /// The shrink into the mini-map as the form appears; quicker after a tap to skip.
    static func settleAnimation(skipped: Bool) -> Animation {
        .smooth(duration: skipped ? 0.3 : CelebrationTimeline.settleDuration)
    }

    var body: some View {
        RecordingTraceMap(trace: trace)
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .matchedGeometryEffect(id: isCelebrating ? Self.hiddenID : CelebrationGeometry.miniMapID, in: namespace)
    }

    private static let hiddenID = "recordingHiddenMiniMap"
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
                    Text(item.caption)
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
