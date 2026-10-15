import SwiftUI

/// Distance left on the followed Itinerary (ADR-031 §7, §8): large, with a progress bar frozen
/// off the track, the state ("Hors Itinéraire", "Chemin recalculé", "Itinéraire terminé")
/// replacing the "Restant sur l'Itinéraire" label.
struct RecordingItineraryPanel: View {
    let itinerary: FollowedItinerary

    var body: some View {
        let item = RecordingFormatters.itinerary(itinerary)
        let isOff = itinerary.state == .offTrack || itinerary.state == .returnPath
        VStack(spacing: 6) {
            Text(item.value)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            ProgressView(value: itinerary.progress.fraction)
                .tint(isOff ? .secondary : Theme.accent)
                .padding(.horizontal, 48)
            Text("\(item.label) (\(item.unit))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(itinerary.state == .offTrack ? .orange : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recordingItineraryRemaining")
    }
}
