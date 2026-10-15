import SwiftUI

/// The Record tab (ADR-031 §2, §8, §11): the pre-start screen, or the Recording in progress
/// with the tab bar hidden, and the finish screen over it.
struct RecordingView: View {
    @State var store: RecordingStore

    var body: some View {
        NavigationStack {
            content
                .toolbar(store.snapshot == nil ? .automatic : .hidden, for: .tabBar)
                .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.observe() }
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
            RecordingPreStartView(store: store)
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
