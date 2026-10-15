import SwiftUI

/// "Démarrer avec cet Itinéraire" (ADR-031 §2, §15), handed down by the app shell: the
/// Itineraries feature never imports Recording.
struct StartRecordingWithItinerary {
    /// A Recording exists: the button reads "Enregistrement en cours" and opens it.
    var isRecording: Bool
    /// Opens the Record tab, on the pre-start screen with the Itinerary chosen (never a Start
    /// by itself), or on the Recording in progress.
    var open: @MainActor (ItineraryID) -> Void
}

extension EnvironmentValues {
    @Entry var startRecordingWithItinerary: StartRecordingWithItinerary?
}

/// The button under an Itinerary's detail; nothing when the app shell gives no action.
struct StartRecordingButton: View {
    let id: ItineraryID

    @Environment(\.startRecordingWithItinerary) private var start

    var body: some View {
        if let start {
            Button {
                start.open(id)
            } label: {
                Label(
                    start.isRecording ? "Enregistrement en cours" : "Démarrer avec cet Itinéraire",
                    systemImage: start.isRecording ? "record.circle" : "play.fill"
                )
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 8)
            .accessibilityIdentifier("startRecordingWithItinerary")
        }
    }
}
