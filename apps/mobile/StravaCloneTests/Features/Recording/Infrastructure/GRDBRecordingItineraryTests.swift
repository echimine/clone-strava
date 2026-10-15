import Foundation
import Testing
@testable import StravaClone

/// The followed Itinerary saved with the Recording (ADR-031 §10): its loaded track, progress
/// and first-snap flag, on an in-memory database with the real migrations.
struct GRDBRecordingItineraryTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let track = SyntheticTrack.through([(0, 0), (400, 0), (400, 400)])

    private func followed() -> FollowedItinerary {
        FollowedItinerary(id: .fixture(7), name: "Tour du parc", track: track, total: Distance(meters: 800))
    }

    private func fix(east: Double, north: Double) -> LocationSample {
        LocationSample(coordinate: SyntheticTrack.point(east: east, north: north), altitude: nil, horizontalAccuracy: 5, timestamp: start)
    }

    @Test func aRecordingWithoutItineraryLoadsWithoutOne() async throws {
        let repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        try await repository.create(Recording(sport: .run, startedAt: start))

        #expect(try await repository.load()?.itinerary == nil)
    }

    @Test func keepsTheFollowedItineraryItsTrackAndItsProgress() async throws {
        let repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        var recording = Recording(sport: .run, startedAt: start)
        try await repository.create(recording)
        var itinerary = followed()
        try await repository.saveItinerary(itinerary, of: recording.id)

        itinerary.progress.update(with: fix(east: 0, north: 0))
        itinerary.progress.update(with: fix(east: 250, north: 0))
        try await repository.saveItineraryProgress(itinerary.progress.saved, of: recording.id)
        recording.pause(at: start.addingTimeInterval(60))
        try await repository.save(recording)

        let stored = try #require(try await repository.load()?.itinerary)
        #expect(stored.id == .fixture(7))
        #expect(stored.name == "Tour du parc")
        #expect(stored.track.count == track.count)
        #expect(stored.progress.status == .onTrack)
        #expect(abs(stored.progress.remaining!.meters - 550) < 1)
    }

    @Test func removingTheItineraryClearsIt() async throws {
        let repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        let recording = Recording(sport: .ride, startedAt: start)
        try await repository.create(recording)
        try await repository.saveItinerary(followed(), of: recording.id)

        try await repository.saveItinerary(nil, of: recording.id)

        #expect(try await repository.load()?.itinerary == nil)
    }
}
