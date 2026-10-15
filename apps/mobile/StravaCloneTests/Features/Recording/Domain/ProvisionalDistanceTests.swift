import Foundation
import Testing
@testable import StravaClone

struct ProvisionalDistanceTests {
    @Test func sharedTracesAreFound() throws {
        let traces = try SharedTrace.all()

        #expect(traces.count >= 3)
        #expect(traces["run-train-during-pause.json"] != nil)
    }

    /// ADR-031 §5: the provisional distance stays within ±1 % of the official one.
    @Test func everySharedTraceStaysWithinOnePercentOfTheOfficialDistance() throws {
        for (name, trace) in try SharedTrace.all() {
            let sport = try #require(trace.sport, "\(name): sport without GPS")

            let distance = ProvisionalDistance.measure(trace.samples, pauses: trace.pauses, sport: sport)

            let error = abs(distance.meters - trace.expected.distanceM) / trace.expected.distanceM
            #expect(error <= 0.01, "\(name): \(distance.meters) m instead of \(trace.expected.distanceM) m")
        }
    }

    @Test func aTrainRideDuringAPauseIsIgnored() throws {
        let trace = try SharedTrace.named("run-train-during-pause.json")

        let distance = ProvisionalDistance.measure(trace.samples, pauses: trace.pauses, sport: .run)
        let withoutPause = ProvisionalDistance.measure(trace.samples, pauses: [], sport: .run)

        #expect(abs(distance.meters - 1_950) < 19.5)
        // Without the Pause, the 60 km leg is a speed jump and its end point is dropped:
        // everything after it is lost as well, so the Pause is what keeps the trace whole.
        #expect(withoutPause.meters < distance.meters)
    }

    @Test func inaccurateFixesAndJumpsAreDroppedLiveToo() {
        var distance = ProvisionalDistance(sport: .walk)
        let origin = Coordinate(latitude: 45.764, longitude: 4.8357)
        let start = Date(timeIntervalSince1970: 1_792_047_600)

        distance.append(sample(origin, at: start))
        distance.append(sample(origin.offset(northMeters: 1.5), at: start.addingTimeInterval(1)))
        // 80 m accuracy: dropped.
        distance.append(sample(origin.offset(northMeters: 40), at: start.addingTimeInterval(2), accuracy: 80))
        // 100 m in 1 s on foot: a GPS jump.
        distance.append(sample(origin.offset(northMeters: 101.5), at: start.addingTimeInterval(2)))
        distance.append(sample(origin.offset(northMeters: 3), at: start.addingTimeInterval(3)))

        #expect(abs(distance.total.meters - 3) < 0.01)
    }

    @Test func theLegAcrossAPauseNeitherCountsNorJumps() {
        var distance = ProvisionalDistance(sport: .run)
        let origin = Coordinate(latitude: 45.764, longitude: 4.8357)
        let start = Date(timeIntervalSince1970: 1_792_047_600)

        distance.append(sample(origin, at: start))
        distance.notePause()
        let leg = distance.append(sample(origin.offset(northMeters: 5_000), at: start.addingTimeInterval(60)))
        distance.append(sample(origin.offset(northMeters: 5_003), at: start.addingTimeInterval(61)))

        #expect(leg == nil)
        #expect(abs(distance.total.meters - 3) < 0.01)
    }

    private func sample(_ coordinate: Coordinate, at date: Date, accuracy: Double = 5) -> LocationSample {
        LocationSample(coordinate: coordinate, altitude: nil, horizontalAccuracy: accuracy, timestamp: date)
    }
}

extension Coordinate {
    /// A point `northMeters` due north on the 6,371 km sphere.
    func offset(northMeters: Double) -> Coordinate {
        Coordinate(latitude: latitude + northMeters / 6_371_008.8 * 180 / .pi, longitude: longitude)
    }
}
