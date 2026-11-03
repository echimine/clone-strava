import SwiftUI

/// "Temps intermédiaires" (ADR-036 §9): Km, Allure (Vitesse), a bar proportional to speed,
/// Élév. and FC, the FC column only when a split has a heart rate.
struct ActivitySplitsSection: View {
    let table: ActivitySplitsTable

    var body: some View {
        ActivityAnalysisCard(title: ActivityAnalysisMessages.splitsTitle) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(ActivityAnalysisMessages.kilometre)
                    Text(table.speedTitle)
                    Color.clear.frame(height: 1).gridCellUnsizedAxes(.vertical)
                    Text(ActivityAnalysisMessages.elevation).gridColumnAlignment(.trailing)
                    if table.showsHeartRate {
                        Text(ActivityAnalysisMessages.heartRate).gridColumnAlignment(.trailing)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(table.rows) { row in
                    GridRow {
                        Text(row.kilometer)
                        Text(row.speed)
                            .fixedSize()
                        bar(row.barFraction)
                        Text(row.elevation ?? "–")
                        if table.showsHeartRate {
                            Text(row.heartRate ?? "–")
                        }
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("activityDetail.splits")
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.accent)
                .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 4 : 0))
                .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// A titled block of the detail's analysis, on the grouped background.
struct ActivityAnalysisCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}
