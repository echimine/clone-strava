#if DEBUG
import SwiftUI

/// Debug only: replays the splash (ADR-032 §4) and the end-of-Recording celebration (§5)
/// without a cold launch or a real outing, to check them on a device. Reached from the
/// Profile tab; absent from Release builds.
struct AnimationsPreviewView: View {
    @State private var splash: SplashPreviewMode?
    @State private var celebration: CelebrationPreviewMode?

    var body: some View {
        Form {
            Section {
                Button("Session immédiate") { splash = .fast }
                Button("Session lente (2,5 s) : le N pulse") { splash = .slow }
            } header: {
                Text("Splash")
            } footer: {
                Text("Avec « Réduire les animations » activé, le splash devient un simple fondu.")
            }
            Section {
                Button("Carte 3D") { celebration = .map }
                Button("Sans carte (repli hors ligne)") { celebration = .sketch }
            } header: {
                Text("Célébration de fin d'enregistrement")
            } footer: {
                Text("Sortie fictive : tour du lac d'Annecy à vélo. Touchez l'animation pour la passer.")
            }
        }
        .navigationTitle("Animations")
        .fullScreenCover(item: $splash) { mode in
            SplashPreview(mode: mode) { splash = nil }
        }
        .fullScreenCover(item: $celebration) { mode in
            CelebrationPreview(mode: mode) { celebration = nil }
        }
    }
}

private enum SplashPreviewMode: String, Identifiable {
    case fast, slow
    var id: String { rawValue }
}

private enum CelebrationPreviewMode: String, Identifiable {
    case map, sketch
    var id: String { rawValue }
}

/// The real `SplashView` over a stand-in app; the session becomes known after a delay.
private struct SplashPreview: View {
    let mode: SplashPreviewMode
    let onClose: () -> Void

    @State private var isSessionKnown = false
    @State private var isSplashPresented = true

    var body: some View {
        VStack(spacing: 16) {
            Text("Accueil")
                .font(.largeTitle.weight(.heavy).italic())
            Text("L'app apparaît ici, à travers le N.")
                .foregroundStyle(.secondary)
            Button("Fermer", action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .overlay {
            if isSplashPresented {
                SplashView(isSessionKnown: isSessionKnown) {
                    isSplashPresented = false
                }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(mode == .slow ? 2.5 : 0.1))
            isSessionKnown = true
        }
    }
}

/// The real `RecordingCelebration` on a fictional outing, ending in a mini-map like the
/// finish screen's.
private struct CelebrationPreview: View {
    let mode: CelebrationPreviewMode
    let onClose: () -> Void

    @Namespace private var space
    @State private var isCelebrating = true
    @State private var replayCount = 0

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                CelebrationMiniMap(trace: PreviewOuting.trace, namespace: space, isCelebrating: isCelebrating)
                Text("La carte s'est rétractée à la place de la mini-carte de l'écran de fin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Rejouer") {
                    replayCount += 1
                    isCelebrating = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Button("Fermer", action: onClose)
                Spacer()
            }
            .padding(Theme.spacing)
            .opacity(isCelebrating ? 0 : 1)
            .allowsHitTesting(!isCelebrating)

            if isCelebrating {
                RecordingCelebration(stats: PreviewOuting.stats, namespace: space, onFinished: { skipped in
                    withAnimation(CelebrationMiniMap.settleAnimation(skipped: skipped)) {
                        isCelebrating = false
                    }
                }) { frame in
                    if mode == .map {
                        CelebrationMapBackground(trace: PreviewOuting.trace, frame: frame)
                    } else {
                        CelebrationSketchBackground(trace: PreviewOuting.trace, progress: frame.traceProgress)
                    }
                }
                .id(replayCount)
                .zIndex(1)
            }
        }
    }
}

/// A fictional ride around Lake Annecy: a wobbly loop, enough relief for the 3D camera.
private enum PreviewOuting {
    static let trace: [Coordinate] = {
        let center = (latitude: 45.845, longitude: 6.19)
        let count = 180
        return (0...count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            let wobble = 1 + 0.06 * sin(7 * angle) + 0.03 * sin(17 * angle)
            return Coordinate(
                latitude: center.latitude + 0.072 * wobble * cos(angle),
                longitude: center.longitude + 0.036 * wobble * sin(angle)
            )
        }
    }()

    static let stats: RecordingStats = {
        let meters = zip(trace, trace.dropFirst()).reduce(0) { total, pair in
            total + pair.0.distance(to: pair.1).meters
        }
        let averageSpeedMs = 7.4
        return RecordingStats(
            sport: .ride,
            elapsed: .seconds(Int(meters / averageSpeedMs)),
            distance: Distance(meters: meters),
            currentSpeedMs: nil
        )
    }()
}
#endif
