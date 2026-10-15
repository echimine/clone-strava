import Foundation
@testable import StravaClone

/// The shared JSON test traces of `packages/contracts/fixtures/traces` (ADR-031 §5), copied
/// into the test bundle as the `traces` folder.
struct SharedTrace: Decodable {
    struct Expected: Decodable {
        let distanceM: Double
        let movingTimeS: Double
        let elapsedTimeS: Double
    }

    struct Point: Decodable {
        let timestampMs: Int64
        let lat: Double
        let lon: Double
        let elevationM: Double?
        let horizontalAccuracyM: Double?
        let speedMs: Double?
    }

    struct Pause: Decodable {
        let startMs: Int64
        let endMs: Int64
    }

    struct Trace: Decodable {
        let points: [Point]
        let pauses: [Pause]
    }

    let description: String
    let sportTypeCode: String
    let expected: Expected
    let trace: Trace

    var sport: RecordingSport? { RecordingSport(rawValue: sportTypeCode) }

    var samples: [LocationSample] {
        trace.points.map { point in
            LocationSample(
                coordinate: Coordinate(latitude: point.lat, longitude: point.lon),
                altitude: point.elevationM,
                horizontalAccuracy: point.horizontalAccuracyM ?? 5,
                speed: point.speedMs,
                timestamp: Date(timeIntervalSince1970: Double(point.timestampMs) / 1_000)
            )
        }
    }

    var pauses: [RecordingPause] {
        trace.pauses.map {
            RecordingPause(
                start: Date(timeIntervalSince1970: Double($0.startMs) / 1_000),
                end: Date(timeIntervalSince1970: Double($0.endMs) / 1_000)
            )
        }
    }

    /// Every trace of the folder, by file name.
    static func all() throws -> [String: SharedTrace] {
        let urls = Bundle(for: BundleToken.self).urls(forResourcesWithExtension: "json", subdirectory: "traces") ?? []
        var traces: [String: SharedTrace] = [:]
        for url in urls {
            traces[url.lastPathComponent] = try JSONDecoder().decode(SharedTrace.self, from: Data(contentsOf: url))
        }
        return traces
    }

    static func named(_ fileName: String) throws -> SharedTrace {
        guard let trace = try all()[fileName] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return trace
    }
}

private final class BundleToken {}
