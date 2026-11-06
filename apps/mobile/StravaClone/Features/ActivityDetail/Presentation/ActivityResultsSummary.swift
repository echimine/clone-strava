import Foundation

/// One line of « Résultats » (ADR-039 §15): the medal, a title (« 1 KM » or the Segment's
/// name), the figures (a Segment's distance, then time and pace), and the Medal's phrase.
struct ActivityResultLine: Identifiable, Hashable, Sendable {
    enum Target: Hashable, Sendable {
        case bestEffort(distanceM: Double)
        case segment(id: String)
    }

    let id: String
    let target: Target
    let medal: Medal?
    let title: String
    let figures: [String]
    let note: String?
    /// The author may remove this Best effort.
    let removable: Bool
    /// The laurel crown: the athlete is the Segment's Local Legend.
    let localLegend: Bool
}

/// What the « Résultats » card shows (spec #252), from the API's answer and the Activity's sport.
struct ActivityResultsSummary: Hashable, Sendable {
    struct Counter: Hashable, Sendable {
        let label: String
        let value: String
    }

    /// Meilleurs efforts, Segments (none for a pool swim), Performances.
    let counters: [Counter]
    /// At most 3 medalled lines: Best efforts first, then Segments in trace order.
    let lines: [ActivityResultLine]
    /// « Recherche des Segments de cette Activité… ».
    let showsMatching: Bool
    /// No section without a result.
    let isEmpty: Bool
    /// « Tous les résultats »: every Best effort, every Segment.
    let allBestEfforts: [ActivityResultLine]
    let allSegments: [ActivityResultLine]

    static let maxLines = 3

    init(results: ActivityResults, sport: SportType) {
        let isPool = results.poolLength != nil
        var counters = [Counter(label: ActivityResultsMessages.bestEfforts, value: Self.number(results.bestEfforts.count))]
        if !isPool {
            counters.append(Counter(
                label: ActivityResultsMessages.segments,
                value: results.matchingInProgress ? "…" : Self.number(results.efforts.count)
            ))
        }
        counters.append(Counter(label: ActivityResultsMessages.performances, value: Self.number(results.medalCount)))
        self.counters = counters
        allBestEfforts = results.bestEfforts.map { Self.line($0, sport: sport) }
        allSegments = results.efforts.map { Self.line($0, sport: sport) }
        lines = Array((allBestEfforts + allSegments).filter { $0.medal != nil }.prefix(Self.maxLines))
        showsMatching = results.matchingInProgress
        isEmpty = results.bestEfforts.isEmpty && results.efforts.isEmpty && !results.matchingInProgress
    }

    static func line(_ effort: BestEffortResult, sport: SportType) -> ActivityResultLine {
        let distance = Distance(meters: effort.distanceM)
        return ActivityResultLine(
            id: "best-\(effort.distanceM)",
            target: .bestEffort(distanceM: effort.distanceM),
            medal: effort.medal,
            title: ActivityResultsFormat.title(distance, sport: sport),
            figures: [
                ActivityResultsFormat.time(effort.elapsedTime),
                ActivityResultsFormat.pace(distance, effort.elapsedTime, sport: sport),
            ],
            note: effort.medal.map(ActivityResultsMessages.bestEffortPhrase),
            removable: effort.removable,
            localLegend: false
        )
    }

    static func line(_ effort: SegmentEffortResult, sport: SportType) -> ActivityResultLine {
        ActivityResultLine(
            id: "segment-\(effort.id)",
            target: .segment(id: effort.segmentID),
            medal: effort.medal,
            title: effort.segmentName,
            figures: [
                ActivityResultsFormat.distance(effort.segmentDistance),
                ActivityResultsFormat.time(effort.elapsedTime),
                ActivityResultsFormat.pace(effort.segmentDistance, effort.elapsedTime, sport: sport),
            ],
            note: effort.medal.map { ActivityResultsMessages.segmentPhrase($0, firstPass: effort.isFirstPass) },
            removable: false,
            localLegend: effort.localLegend
        )
    }

    private static func number(_ value: Int) -> String {
        value.formatted(.number.locale(ActivityFormatters.locale))
    }
}

/// Figures of « Résultats », as Strava writes them.
enum ActivityResultsFormat {
    /// « 1 KM », « 400 M », « 1,5 KM », « SEMI-MARATHON », « MARATHON »; meters in the water.
    static func title(_ distance: Distance, sport: SportType) -> String {
        switch distance.meters {
        case 21_097.5: return ActivityResultsMessages.halfMarathon
        case 42_195: return ActivityResultsMessages.marathon
        default: break
        }
        if sport == .swim || distance.meters < 1_000 {
            return "\(Int(distance.meters.rounded())) M"
        }
        let kilometers = distance.kilometers.formatted(.number.precision(.fractionLength(0...1)).locale(ActivityFormatters.locale))
        return "\(kilometers) KM"
    }

    /// « 0,37 km »: a Segment's length.
    static func distance(_ distance: Distance) -> String {
        "\(distance.kilometers.formatted(.number.precision(.fractionLength(2)).locale(ActivityFormatters.locale))) km"
    }

    /// « 4:40 », « 1:02:03 ».
    static func time(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds) + (duration.components.attoseconds >= 500_000_000_000_000_000 ? 1 : 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// km/h by bike, /100 m in the water, /km otherwise.
    static func pace(_ distance: Distance, _ duration: Duration, sport: SportType) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        guard distance.meters > 0, seconds > 0 else { return "–" }
        switch sport {
        case .ride:
            return ActivityFormatters.speed(metersPerSecond: distance.meters / seconds)
        case .swim:
            return "\(time(.seconds(Int((seconds / distance.meters * 100).rounded())))) /100 m"
        default:
            return "\(time(.seconds(Int((seconds / distance.kilometers).rounded())))) /km"
        }
    }
}
