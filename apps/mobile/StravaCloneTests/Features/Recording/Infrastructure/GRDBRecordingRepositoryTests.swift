import Foundation
import Testing
@testable import StravaClone

struct GRDBRecordingRepositoryTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    private func makeRepository() throws -> GRDBRecordingRepository {
        GRDBRecordingRepository(database: try AppDatabase.inMemory())
    }

    private func point(_ seconds: TimeInterval, north: Double = 0) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: 45.764, longitude: 4.8357).offset(northMeters: north),
            altitude: 170.5,
            horizontalAccuracy: 4,
            speed: 3,
            timestamp: at(seconds)
        )
    }

    @Test func storesTheRecordingInProgress() async throws {
        let repository = try makeRepository()
        let recording = Recording(sport: .hike, startedAt: start)

        try await repository.create(recording)
        let stored = try await repository.load()

        #expect(stored?.recording == recording)
        #expect(stored?.points == [])
    }

    @Test func holdsOneRecordingAtMost() async throws {
        let repository = try makeRepository()
        try await repository.create(Recording(sport: .run, startedAt: start))

        await #expect(throws: RecordingRepositoryError.alreadyExists) {
            try await repository.create(Recording(sport: .ride, startedAt: at(10)))
        }
        #expect(try await repository.load()?.recording.sport == .run)
    }

    @Test func writesPointsOutsidePausesOnly() async throws {
        let repository = try makeRepository()
        var recording = Recording(sport: .run, startedAt: start)
        try await repository.create(recording)

        #expect(try await repository.append(point(1), to: recording.id))
        recording.pause(at: at(2))
        try await repository.save(recording)
        #expect(try await repository.append(point(3, north: 500), to: recording.id) == false)
        recording.resume(at: at(4))
        try await repository.save(recording)
        #expect(try await repository.append(point(5, north: 3), to: recording.id))

        let stored = try #require(try await repository.load())
        #expect(stored.points == [point(1), point(5, north: 3)])
        #expect(stored.recording.pauses == [RecordingPause(start: at(2), end: at(4))])
        #expect(stored.recording.phase == .active)
    }

    @Test func keepsTheOpenPauseAndThePhase() async throws {
        let repository = try makeRepository()
        var recording = Recording(sport: .walk, startedAt: start)
        try await repository.create(recording)
        recording.pause(at: at(61))
        recording.finish()

        try await repository.save(recording)

        let stored = try #require(try await repository.load())
        #expect(stored.recording.phase == .finishing)
        #expect(stored.recording.endedAt == at(61))
    }

    @Test func ignoresPointsOfAnotherRecording() async throws {
        let repository = try makeRepository()
        try await repository.create(Recording(sport: .run, startedAt: start))

        #expect(try await repository.append(point(1), to: ActivityID()) == false)
        #expect(try await repository.load()?.points == [])
    }

    @Test func deleteWipesTheRecordingItsPointsAndItsPauses() async throws {
        let repository = try makeRepository()
        var recording = Recording(sport: .run, startedAt: start)
        try await repository.create(recording)
        try await repository.append(point(1), to: recording.id)
        recording.pause(at: at(2))
        recording.resume(at: at(3))
        try await repository.save(recording)
        try await repository.append(point(4, north: 3), to: recording.id)

        try await repository.delete(recording.id)

        #expect(try await repository.load() == nil)
        // A Recording under the same UUID finds nothing left behind.
        try await repository.create(Recording(id: recording.id, sport: .run, startedAt: at(10)))
        let fresh = try #require(try await repository.load())
        #expect(fresh.points.isEmpty)
        #expect(fresh.recording.pauses.isEmpty)
    }
}

