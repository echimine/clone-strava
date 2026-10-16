import Foundation

/// One cell of the detail's stats grid: "Allure moy." above "5:00 /km".
struct ActivityStatItem: Hashable, Identifiable {
    let label: String
    let value: String
    var id: String { label }

    /// The stats shown for this sport, in display order (ADR-033 §3): a stat only when it is
    /// not null and the sport tracks it, pace or speed after the sport's `paceUnit`, heart rate
    /// and calories only when present. Formats are `ActivityCard`'s.
    static func items(for stats: ActivityStats, sport: SportType) -> [ActivityStatItem] {
        var items: [ActivityStatItem] = []
        func add(_ label: String, _ value: String?) {
            if let value { items.append(ActivityStatItem(label: label, value: value)) }
        }
        let distance = sport.tracksDistance
        let pace = sport.paceUnit == .pace

        if distance {
            add("Distance", stats.distance.map(ActivityFormatters.distance))
            add(pace ? "Allure moy." : "Vitesse moy.", stats.avgSpeedMs.flatMap { speedText($0, pace: pace) })
        }
        add("Temps", stats.movingTime.map(ActivityFormatters.duration))
        add("Temps écoulé", stats.elapsedTime.map(ActivityFormatters.duration))
        if sport.tracksElevation {
            add("Dénivelé", stats.elevationGain.map(ActivityFormatters.elevation))
        }
        if distance {
            add(pace ? "Allure max" : "Vitesse max", stats.maxSpeedMs.flatMap { speedText($0, pace: pace) })
        }
        add("FC moy.", stats.avgHeartRate.map { "\($0) bpm" })
        add("FC max", stats.maxHeartRate.map { "\($0) bpm" })
        add("Calories", stats.calories.map { "\($0.formatted(.number.locale(ActivityFormatters.locale))) kcal" })
        return items
    }

    private static func speedText(_ metersPerSecond: Double, pace: Bool) -> String? {
        guard metersPerSecond > 0 else { return nil }
        return pace
            ? ActivityFormatters.pace(metersPerSecond: metersPerSecond)
            : ActivityFormatters.speed(metersPerSecond: metersPerSecond)
    }
}
