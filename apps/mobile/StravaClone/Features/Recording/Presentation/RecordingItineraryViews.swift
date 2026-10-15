import SwiftUI

/// Distance left on the followed Itinerary (ADR-031 §8): large, with a progress bar, the state
/// ("Hors Itinéraire", "Itinéraire terminé") replacing the "Restant sur l'Itinéraire" label.
struct RecordingItineraryPanel: View {
    let progress: ItineraryProgress

    var body: some View {
        let item = RecordingFormatters.itinerary(progress)
        VStack(spacing: 6) {
            Text(item.value)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            ProgressView(value: progress.fraction)
                .tint(progress.status == .offTrack ? .secondary : Theme.accent)
                .padding(.horizontal, 48)
            Text("\(item.label) (\(item.unit))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(progress.status == .offTrack ? .orange : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recordingItineraryRemaining")
    }
}
