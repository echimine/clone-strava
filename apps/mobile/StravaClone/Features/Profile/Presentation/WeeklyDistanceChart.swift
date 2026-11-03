import Charts
import SwiftUI

/// "12 dernières semaines" (ADR-036 §4, §10): the distance of each week in `Theme.accent`, the
/// current week marked by a larger point. Touching the chart (`chartXSelection`) picks a week.
struct WeeklyDistanceChart: View {
    let progress: AthleteProgress
    @Binding var selectedDate: Date?

    private struct Point: Identifiable {
        let date: Date
        let kilometers: Double
        let isCurrent: Bool
        var id: Date { date }
    }

    private var points: [Point] {
        let lastIndex = progress.weeks.count - 1
        return progress.weeks.enumerated().compactMap { index, week in
            week.weekStart.startInParis.map { Point(date: $0, kilometers: week.distance.kilometers, isCurrent: index == lastIndex) }
        }
    }

    private var selectedPoint: Point? {
        guard let selectedDate, let week = progress.week(containing: selectedDate) else { return nil }
        return points.first { $0.date == week.weekStart.startInParis }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Semaine", point.date), y: .value("Distance", point.kilometers))
                    .foregroundStyle(Theme.accent.opacity(0.15))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Semaine", point.date), y: .value("Distance", point.kilometers))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Semaine", point.date), y: .value("Distance", point.kilometers))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(point.isCurrent ? 120 : 30)
            }
            if let selectedPoint {
                RuleMark(x: .value("Semaine", selectedPoint.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Semaine", selectedPoint.date), y: .value("Distance", selectedPoint.kilometers))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(160)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: points.enumerated().filter { $0.offset % 3 == 2 }.map(\.element.date)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.axisLabel(date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kilometers = value.as(Double.self) {
                        Text("\(Int(kilometers.rounded())) km")
                    }
                }
            }
        }
        .frame(height: 180)
        .accessibilityElement()
        .accessibilityLabel(StatisticsMessages.lastTwelveWeeks)
        .accessibilityValue(points.map { "\(Self.axisLabel($0.date)) : \(ActivityFormatters.distance(Distance(meters: $0.kilometers * 1_000)))" }.joined(separator: ", "))
        .accessibilityIdentifier("profile.progress.chart")
    }

    /// "3 nov.".
    private static func axisLabel(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: ActivityFormatters.locale, timeZone: ProgressCalendar.timeZone)
                .day()
                .month(.abbreviated)
        )
    }
}
