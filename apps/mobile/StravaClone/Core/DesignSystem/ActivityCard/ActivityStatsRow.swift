import SwiftUI

/// Distance, elevation gain and moving time, Strava style: small label above a big value.
struct ActivityStatsRow: View {
    let post: ActivityPost

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("Distance", post.distance.map(ActivityFormatters.distance))
            Divider().frame(height: 36)
            stat("Dénivelé", post.elevationGain.map(ActivityFormatters.elevation))
            Divider().frame(height: 36)
            stat("Temps", post.movingTime.map(ActivityFormatters.duration))
        }
    }

    private func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "–")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}
