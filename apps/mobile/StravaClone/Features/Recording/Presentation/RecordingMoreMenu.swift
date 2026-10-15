import SwiftUI

/// The auto-pause switch of the pre-start screen (ADR-031 §2, §4), for a sport that offers it.
struct RecordingAutoPauseToggle: View {
    let store: RecordingStore

    var body: some View {
        Toggle(isOn: binding(store)) {
            Label(RecordingMessages.autoPause, systemImage: "pause.circle")
                .font(.subheadline.weight(.semibold))
        }
        .tint(Theme.accent)
        .accessibilityIdentifier("recordingAutoPauseToggle")
    }
}

/// The "…" menu of the Recording header (ADR-031 §8): the auto-pause switch, for a sport that
/// offers it, and "Retirer l'Itinéraire" with confirmation, while one is followed. Hidden when it
/// has nothing to offer. Switching auto-pause off during an automatic Pause leaves the Recording
/// paused.
struct RecordingMoreMenu: View {
    let store: RecordingStore
    let snapshot: RecordingSnapshot

    @State private var confirmsRemoval = false

    var body: some View {
        if store.offersAutoPause || snapshot.itinerary != nil {
            Menu {
                if store.offersAutoPause {
                    Toggle(RecordingMessages.autoPause, systemImage: "pause.circle", isOn: binding(store))
                }
                if snapshot.itinerary != nil {
                    Button(RecordingMessages.removeItinerary, systemImage: "xmark.circle", role: .destructive) {
                        confirmsRemoval = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Plus")
            .accessibilityIdentifier("recordingMoreMenu")
            .confirmationDialog(RecordingMessages.removeItineraryTitle, isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button(RecordingMessages.removeItinerary, role: .destructive) {
                    Task { await store.removeItinerary() }
                }
            } message: {
                Text(RecordingMessages.removeItineraryMessage)
            }
        }
    }
}

@MainActor
private func binding(_ store: RecordingStore) -> Binding<Bool> {
    Binding(
        get: { store.autoPause },
        set: { enabled in Task { await store.setAutoPause(enabled) } }
    )
}
