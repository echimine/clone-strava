import SwiftUI

/// The card's three stats, chosen by sport (ADR-036 §5), Strava style: small label above a
/// big value; then « Performances » when the Activity has a Medal (ADR-039 §15).
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
            if let medals = ActivityCardStat.performances(for: post) {
                Divider().frame(height: 36)
                performances(medals)
            }
        }
    }

    /// The three ribbon medals, then the Medal count.
    private func performances(_ medals: MedalCounts) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ActivityCardMessages.performances)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 1) {
                ForEach(Medal.allCases, id: \.self) { MedalRibbon($0, size: 16) }
                Text(medals.total.formatted())
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.leading, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ActivityCardMessages.performances)
        .accessibilityValue(ActivityCardMessages.medalCount(medals.total))
        .accessibilityIdentifier("activityCard.performances")
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
