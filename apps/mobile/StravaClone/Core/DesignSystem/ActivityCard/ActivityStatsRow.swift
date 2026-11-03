import SwiftUI

/// The card's three stats, chosen by sport (ADR-036 §5), Strava style: small label above a
/// big value.
struct ActivityStatsRow: View {
    let post: ActivityPost

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(ActivityCardStat.stats(for: post).enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Divider().frame(height: 36)
                }
                cell(stat)
            }
        }
    }

    private func cell(_ stat: ActivityCardStat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(stat.value)
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
