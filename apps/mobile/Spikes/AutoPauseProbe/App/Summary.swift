import Foundation

/// Delays measured from each marker, until the next marker (or the end of the session).
struct MarkerResult: Identifiable {
    struct Row: Identifiable {
        let label: String
        let seconds: Double?
        var id: String { label }
    }

    let t: Double
    let mark: String
    let rows: [Row]
    var id: Double { t }
}

struct BatteryResult {
    let startLevel: Float
    let lastLevel: Float
    let hours: Double
    var percentPerHour: Double? { hours > 0.05 ? Double(startLevel - lastLevel) * 100 / hours : nil }
}

enum Summary {
    /// A fix counts as "moving" at or above this GPS speed (m/s).
    static let movingSpeed = 0.5
    /// Resume: first fix at or above this speed after a "go" marker (m/s).
    static let resumeSpeed = 1.0
    /// Strava's 2014 cycling rule: pause after this many seconds without a moving fix.
    static let stravaGap = 10.0

    static func markers(in events: ArraySlice<Event>) -> [MarkerResult] {
        let list = Array(events)
        let end = list.last?.t ?? Date().timeIntervalSince1970
        let marks = list.filter { $0.kind == "marker" }
        return marks.enumerated().map { index, marker in
            let windowEnd = index + 1 < marks.count ? marks[index + 1].t : end
            let window = list.filter { $0.t >= marker.t && $0.t <= windowEnd }
            return marker.mark == "stop"
                ? stopResult(marker, window: window, all: list, windowEnd: windowEnd)
                : goResult(marker, window: window)
        }
    }

    private static func stopResult(_ marker: Event, window: [Event], all: [Event], windowEnd: Double) -> MarkerResult {
        let t0 = marker.t
        let stationary = window.first { $0.stationary == true || ($0.flags ?? []).contains("stationary") }
        let motion = window.first { $0.kind == "motion" && ($0.activity ?? "").contains("stationary") }
        let rows: [MarkerResult.Row] = [
            .init(label: "isStationary reçu", seconds: stationary.map { $0.t - t0 }),
            .init(label: "Core Motion « stationary » reçu", seconds: motion.map { $0.t - t0 }),
            .init(label: "Core Motion « stationary » daté par iOS", seconds: motion?.start.map { $0 - t0 }),
            .init(label: "Règle Strava (\(Int(stravaGap)) s sans point ≥ \(movingSpeed) m/s)",
                  seconds: stravaRule(t0: t0, all: all, windowEnd: windowEnd).map { $0 - t0 }),
            .init(label: "Dernier point GPS de la fenêtre", seconds: window.last { $0.kind == "loc" }.map { $0.t - t0 }),
        ]
        return MarkerResult(t: t0, mark: "stop", rows: rows)
    }

    private static func goResult(_ marker: Event, window: [Event]) -> MarkerResult {
        let t1 = marker.t
        let fix = window.first { $0.kind == "loc" }
        let moving = window.first { $0.kind == "loc" && ($0.spd ?? -1) >= resumeSpeed }
        let motion = window.first {
            guard $0.kind == "motion", let activity = $0.activity else { return false }
            return !activity.contains("stationary")
                && ["walking", "running", "cycling"].contains { activity.contains($0) }
        }
        let rows: [MarkerResult.Row] = [
            .init(label: "1er point GPS", seconds: fix.map { $0.t - t1 }),
            .init(label: "1er point ≥ \(resumeSpeed) m/s", seconds: moving.map { $0.t - t1 }),
            .init(label: "Core Motion en mouvement reçu", seconds: motion.map { $0.t - t1 }),
            .init(label: "Core Motion en mouvement daté par iOS", seconds: motion?.start.map { $0 - t1 }),
        ]
        return MarkerResult(t: t1, mark: "go", rows: rows)
    }

    /// When Strava's phone rule would have paused: first instant ≥ t0 with no moving fix for `stravaGap` s.
    private static func stravaRule(t0: Double, all: [Event], windowEnd: Double) -> Double? {
        let moving = all.filter { $0.isMovingFix && $0.t <= windowEnd }.map(\.t)
        var previous = moving.last { $0 <= t0 } ?? (t0 - stravaGap)
        for t in moving where t > t0 {
            if t - previous >= stravaGap { break }
            previous = t
        }
        let fire = max(previous + stravaGap, t0)
        return fire <= windowEnd ? fire : nil
    }

    static func battery(in events: ArraySlice<Event>) -> BatteryResult? {
        let readings = events.filter { $0.kind == "battery" && ($0.level ?? -1) >= 0 }
        guard let first = readings.first, let last = readings.last,
              let startLevel = first.level, let lastLevel = last.level else { return nil }
        return BatteryResult(startLevel: startLevel, lastLevel: lastLevel, hours: (last.t - first.t) / 3600)
    }
}
