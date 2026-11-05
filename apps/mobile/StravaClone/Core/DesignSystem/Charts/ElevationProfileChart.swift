import Charts
import SwiftUI

/// Altitude against the distance covered (ADR-030 §3), drawn from the cached track.
struct ElevationProfileChart: View {
    let profile: ElevationProfile

    var body: some View {
        Chart(Array(profile.points.enumerated()), id: \.offset) { _, point in
            AreaMark(
                x: .value("Distance", point.distance.kilometers),
                yStart: .value("Altitude", yDomain.lowerBound),
                yEnd: .value("Altitude", point.altitude)
            )
            .foregroundStyle(Theme.accent.opacity(0.2))
            LineMark(
                x: .value("Distance", point.distance.kilometers),
                y: .value("Altitude", point.altitude)
            )
            .foregroundStyle(Theme.accent)
            .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: 0...max(totalKilometers, 0.001))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kilometers = value.as(Double.self) {
                        Text("\(kilometers.formatted(.number.precision(.fractionLength(0...1)).locale(ActivityFormatters.locale))) km")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let meters = value.as(Double.self) {
                        Text(ActivityFormatters.elevation(meters))
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(ItineraryMessages.elevationProfile)
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("itineraryElevationProfile")
    }

    private var totalKilometers: Double {
        profile.points.last?.distance.kilometers ?? 0
    }

    /// Some room under the lowest point and over the highest; at least 50 m tall so a flat
    /// track does not look like a climb.
    private var yDomain: ClosedRange<Double> {
        guard let range = profile.altitudeRange else { return 0...100 }
        let height = max(range.upperBound - range.lowerBound, 50)
        let middle = (range.lowerBound + range.upperBound) / 2
        return (middle - height * 0.6)...(middle + height * 0.6)
    }

    private var accessibilitySummary: String {
        guard let range = profile.altitudeRange else { return "" }
        return "De \(ActivityFormatters.elevation(range.lowerBound)) à \(ActivityFormatters.elevation(range.upperBound)) d'altitude"
    }
}
