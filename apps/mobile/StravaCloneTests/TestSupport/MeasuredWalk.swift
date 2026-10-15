import Foundation
@testable import StravaClone

/// The walk measured on an iPhone with the bench of #56 (`autopause-measured-walk.json`):
/// GPS fixes, Core Motion readings and the stops the athlete marked on screen.
struct MeasuredWalk: Decodable {
    struct Stop: Decodable {
        let stopMs: Int64
        /// `nil`: still stopped at the end.
        let goMs: Int64?
    }

    struct Location: Decodable {
        let timestampMs: Int64
        let lat: Double
        let lon: Double
        let horizontalAccuracyM: Double
        let speedMs: Double?
    }

    struct Motion: Decodable {
        let startMs: Int64
        let activity: String
        let confidence: Int
    }

    let stops: [Stop]
    let locations: [Location]
    let motion: [Motion]

    static func load() throws -> MeasuredWalk {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "autopause-measured-walk", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(MeasuredWalk.self, from: Data(contentsOf: url))
    }

    /// Every fix and Core Motion reading, in time order.
    var signals: [AutoPauseSignal] {
        let fixes = locations.map { location in
            AutoPauseSignal.location(LocationSample(
                coordinate: Coordinate(latitude: location.lat, longitude: location.lon),
                altitude: nil,
                horizontalAccuracy: location.horizontalAccuracyM,
                speed: location.speedMs,
                timestamp: Date(epochMilliseconds: location.timestampMs)
            ))
        }
        let readings = motion.map { reading in
            AutoPauseSignal.motion(MotionReading(
                activity: Self.activity(reading.activity),
                confidence: MotionConfidence(rawValue: reading.confidence) ?? .low,
                startDate: Date(epochMilliseconds: reading.startMs)
            ))
        }
        return (fixes + readings).enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
    }

    /// Whether the athlete had marked a stop at `date`.
    func isStopped(at date: Date) -> Bool {
        let ms = date.epochMilliseconds
        return stops.contains { ms >= $0.stopMs && ms <= ($0.goMs ?? .max) }
    }

    private static func activity(_ name: String) -> MotionActivity {
        switch name {
        case "stationary": .stationary
        case "walking": .walking
        case "running": .running
        default: .other
        }
    }
}

private final class BundleToken {}
