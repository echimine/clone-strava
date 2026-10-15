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

/// The "…" menu of the Recording screen (ADR-031 §8): the auto-pause switch, for a sport that
/// offers it. Switching it off during an automatic Pause leaves the Recording paused.
struct RecordingMoreMenu: View {
    let store: RecordingStore

    var body: some View {
        if store.offersAutoPause {
            Menu {
                Toggle(RecordingMessages.autoPause, systemImage: "pause.circle", isOn: binding(store))
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Options")
            .accessibilityIdentifier("recordingMoreMenu")
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
