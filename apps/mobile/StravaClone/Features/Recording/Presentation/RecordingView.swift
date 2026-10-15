import SwiftUI

/// The Record tab (ADR-031 §2, §8, §11): the pre-start screen, or the Recording in progress
/// with the tab bar hidden, and the finish screen over it.
struct RecordingView: View {
    @State var store: RecordingStore
    /// "Créer un Itinéraire" from the empty Itinerary chip.
    var onCreateItinerary: () -> Void = {}

    var body: some View {
        NavigationStack {
            content
                .toolbar(store.snapshot == nil ? .automatic : .hidden, for: .tabBar)
                .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.observe() }
        .toast($store.toast)
        .fullScreenCover(isPresented: .constant(store.screen == .finishing)) {
            if let snapshot = store.snapshot {
                RecordingFinishView(store: store, snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.screen {
        case .loading:
            ProgressView()
        case .preStart:
            RecordingPreStartView(store: store, onCreateItinerary: onCreateItinerary)
        case .recording, .finishing:
            if let snapshot = store.snapshot {
                RecordingLiveView(store: store, snapshot: snapshot)
            }
        }
    }
}

/// Yellow of the "EN PAUSE" banner (ADR-031 §8).
extension Color {
    static let recordingPause = Color(red: 1, green: 0.78, blue: 0.2)
}

/// The GPS indicator fed by the shared GPS source (with replay of the last fix): a stationary
/// device sends no new fix, which must not read "Recherche du GPS…".
struct RecordingGPSStatus: View {
    @Environment(LocationPermissionService.self) private var permission
    @Environment(\.locationProvider) private var locationProvider
    @State private var position: LocationSample?

    var body: some View {
        RecordingGPSChip(indicator: GPSIndicator(position: position, isAccuracyReduced: permission.isAccuracyReduced))
            .task(id: permission.isAuthorized) {
                guard permission.isAuthorized, let locationProvider else { return }
                for await sample in await locationProvider.samples() {
                    position = sample
                }
            }
    }
}

/// "Recherche du GPS…", "GPS prêt" or "Position approximative" (ADR-031 §2).
struct RecordingGPSChip: View {
    let indicator: GPSIndicator

    var body: some View {
        Label(text, systemImage: indicator == .ready ? "location.fill" : "location.slash")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassBackground(in: Capsule())
            .accessibilityIdentifier("recordingGPSIndicator")
    }

    private var text: String {
        switch indicator {
        case .searching: "Recherche du GPS…"
        case .ready: "GPS prêt"
        case .approximate: "Position approximative"
        }
    }

    private var color: Color {
        switch indicator {
        case .searching: .secondary
        case .ready: .green
        case .approximate: .orange
        }
    }
}
