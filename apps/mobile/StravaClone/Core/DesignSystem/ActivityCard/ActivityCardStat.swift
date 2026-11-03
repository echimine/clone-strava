import Foundation

/// One of the card's three stats: a small label above a big value (ADR-036 §5).
struct ActivityCardStat: Hashable, Sendable {
    let label: String
    let value: String

    /// Distance · Allure · Temps for a `pace` sport, Distance · Dénivelé · Temps for a `speed`
    /// sport. Allure comes from the average moving speed, Temps is the moving time; a value
    /// that was not measured shows "–".
    static func stats(for post: ActivityPost) -> [ActivityCardStat] {
        let middle = switch post.sport.paceUnit {
        case .pace:
            ActivityCardStat(
                label: ActivityCardMessages.pace,
                value: show(post.avgSpeedMs.flatMap { ActivityFormatters.pace(metersPerSecond: $0) })
            )
        case .speed:
            ActivityCardStat(
                label: ActivityCardMessages.elevation,
                value: show(post.elevationGain.map(ActivityFormatters.elevation))
            )
        }
        return [
            ActivityCardStat(label: ActivityCardMessages.distance, value: show(post.distance.map(ActivityFormatters.distance))),
            middle,
            ActivityCardStat(label: ActivityCardMessages.time, value: show(post.movingTime.map(ActivityFormatters.duration))),
        ]
    }

    private static func show(_ value: String?) -> String {
        value ?? "–"
    }
}
