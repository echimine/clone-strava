import Charts
import SwiftUI

/// "Allure" ("Vitesse" for a `speed` sport, ADR-036 §9): the curve in `Theme.accent` over
/// the altitude in grey, faster higher, then the summary rows.
struct ActivitySpeedSection: View {
    let chart: ActivitySpeedChartData
    let rows: [ActivityStatItem]

    var body: some View {
        ActivityAnalysisCard(title: chart.isPace ? ActivityAnalysisMessages.pace : ActivityAnalysisMessages.speed) {
            Chart {
                ForEach(chart.altitude) { point in
                    AreaMark(
                        x: .value("Distance", point.kilometers),
                        yStart: .value("Base", chart.domain.lowerBound),
                        yEnd: .value("Altitude", point.value),
                        series: .value("Courbe", "altitude")
                    )
                    .foregroundStyle(Color(.systemGray4))
                }
                ForEach(chart.points) { point in
                    LineMark(
                        x: .value("Distance", point.kilometers),
                        y: .value(chart.isPace ? "Allure" : "Vitesse", point.value),
                        series: .value("Courbe", "vitesse")
                    )
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
            .chartYScale(domain: chart.domain)
            .chartXScale(domain: 0...max(chart.totalKilometers, 0.001))
            .chartXAxis { ActivityChartAxes.distance }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(chart.axisLabel(number))
                        }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityElement()
            .accessibilityLabel(chart.isPace ? ActivityAnalysisMessages.pace : ActivityAnalysisMessages.speed)
            .accessibilityValue(rows.map { "\($0.label) \($0.value)" }.joined(separator: ", "))

            ActivitySummaryRows(rows: rows)
        }
        .accessibilityIdentifier("activityDetail.speed")
    }
}

/// "Fréquence cardiaque" (ADR-036 §9): the curve, then FC moyenne and FC max.
struct ActivityHeartRateSection: View {
    let chart: ActivityHeartRateChartData
    let rows: [ActivityStatItem]

    var body: some View {
        ActivityAnalysisCard(title: ActivityAnalysisMessages.heartRateTitle) {
            Chart(chart.points) { point in
                LineMark(
                    x: .value("Distance", point.kilometers),
                    y: .value("FC", point.value)
                )
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            .chartYScale(domain: chart.domain)
            .chartXScale(domain: 0...max(chart.totalKilometers, 0.001))
            .chartXAxis { ActivityChartAxes.distance }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bpm = value.as(Double.self) {
                            Text("\(Int(bpm.rounded()))")
                        }
                    }
                }
            }
            .frame(height: 160)
            .accessibilityElement()
            .accessibilityLabel(ActivityAnalysisMessages.heartRateTitle)
            .accessibilityValue(rows.map { "\($0.label) \($0.value)" }.joined(separator: ", "))

            ActivitySummaryRows(rows: rows)
        }
        .accessibilityIdentifier("activityDetail.heartRate")
    }
}

/// The distance axis shared by the detail's charts: "0 km", "2,5 km"…
enum ActivityChartAxes {
    static var distance: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let kilometers = value.as(Double.self) {
                    Text(ActivityAnalysisMessages.distanceAxis(kilometers))
                }
            }
        }
    }
}

/// "Allure moyenne   5:00 /km" lines under a chart.
struct ActivitySummaryRows: View {
    let rows: [ActivityStatItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.value)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if row != rows.last {
                    Divider()
                }
            }
        }
    }
}
