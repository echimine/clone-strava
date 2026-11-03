import Foundation

/// One sample of a detail chart: a value at a distance.
struct ActivityChartPoint: Hashable, Identifiable {
    let id: Int
    let kilometers: Double
    let value: Double
}

/// What the Allure (Vitesse) chart plots (ADR-036 §9). For a `pace` sport the value is the
/// pace in seconds per kilometre, negated so that faster is higher (the reversed axis); stops
/// and crawls sit at the slowest pace, capped at 1.5 × the median so they do not flatten the
/// rest. For a `speed` sport it is km/h from 0. The altitude is scaled into the bottom 40 % of
/// the plot, under the curve.
struct ActivitySpeedChartData: Hashable {
    let isPace: Bool
    let points: [ActivityChartPoint]
    /// Empty without elevation.
    let altitude: [ActivityChartPoint]
    let domain: ClosedRange<Double>
    let totalKilometers: Double

    private static let altitudeShare = 0.4
    private static let minimumAltitudeSpan = 50.0

    init(series: ActivitySeries, sport: SportType) {
        isPace = sport.paceUnit == .pace
        let kilometers = series.distanceM.map { $0 / 1_000 }
        totalKilometers = kilometers.last ?? 0
        let values: [Double]
        if isPace {
            let moving = series.speedMs.filter { $0 > 0 }.map { (1_000 / $0).rounded() }
            let fastest = moving.min() ?? 180
            let slowest = min(moving.max() ?? 600, Self.median(moving).map { $0 * 1.5 } ?? .infinity)
            values = series.speedMs.map { speed in
                -(speed > 0 ? min((1_000 / speed).rounded(), slowest) : slowest)
            }
            let padding = max((slowest - fastest) * 0.1, 5)
            domain = (-slowest - padding)...(-fastest + padding)
        } else {
            values = series.speedMs.map { max($0, 0) * 3.6 }
            let fastest = values.max() ?? 0
            domain = 0...(fastest + max(fastest * 0.1, 1))
        }
        points = zip(kilometers, values).enumerated().map { ActivityChartPoint(id: $0, kilometers: $1.0, value: $1.1) }

        if let altitudeM = series.altitudeM, let low = altitudeM.min(), let high = altitudeM.max() {
            let span = max(high - low, Self.minimumAltitudeSpan)
            let height = (domain.upperBound - domain.lowerBound) * Self.altitudeShare
            let bottom = domain.lowerBound
            altitude = zip(kilometers, altitudeM).enumerated().map { index, sample in
                ActivityChartPoint(id: index, kilometers: sample.0, value: bottom + (sample.1 - low) / span * height)
            }
        } else {
            altitude = []
        }
    }

    /// "4:10" for a pace, "36 km/h" for a speed.
    func axisLabel(_ value: Double) -> String {
        if isPace {
            let seconds = Int((-value).rounded())
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        }
        return "\(Int(value.rounded())) km/h"
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// What the Fréquence cardiaque chart plots: bpm against the distance, missing samples (0)
/// left out.
struct ActivityHeartRateChartData: Hashable {
    let points: [ActivityChartPoint]
    let domain: ClosedRange<Double>
    let totalKilometers: Double

    /// Nil when the series has no heart rate.
    init?(series: ActivitySeries) {
        guard let heartRate = series.heartRateBpm else { return nil }
        let samples = zip(series.distanceM, heartRate).filter { $0.1 > 0 }
        guard let low = samples.map(\.1).min(), let high = samples.map(\.1).max() else { return nil }
        points = samples.enumerated().map { ActivityChartPoint(id: $0, kilometers: $1.0 / 1_000, value: Double($1.1)) }
        domain = Double(low - 5)...Double(high + 5)
        totalKilometers = (series.distanceM.last ?? 0) / 1_000
    }
}
