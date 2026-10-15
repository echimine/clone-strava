import Foundation
import Testing
@testable import StravaClone

/// Following an Itinerary during a Recording (ADR-031 §6, §10): progress from the real
/// positions, during a Pause too, saved with the Recording and picked up on resume.
@MainActor
struct RecordingServiceItineraryTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let provider = FakeLocationProvider()
    private let clock: Locked<Date>
    private let repository: GRDBRecordingRepository
    private let service: RecordingService
    /// A 400 m square, start = finish.
    private let loop = SyntheticTrack.through([(0, 0), (400, 0), (400, 400), (0, 400), (0, 0)])

    init() throws {
        let clock = Locked(start)
        self.clock = clock
        repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        service = RecordingService(locationProvider: provider, repository: repository, now: { clock.value })
    }

    private var followed: FollowedItinerary {
        FollowedItinerary(id: .fixture(3), name: "Boucle", track: loop, total: Distance(meters: 1_600))
    }

    private func fix(_ seconds: TimeInterval, east: Double, north: Double) -> LocationSample {
        clock.value = start.addingTimeInterval(seconds)
        return LocationSample(
            coordinate: SyntheticTrack.point(east: east, north: north),
            altitude: nil,
            horizontalAccuracy: 5,
            timestamp: start.addingTimeInterval(seconds)
        )
    }

    private func remaining(_ snapshot: RecordingSnapshot?) -> Double? {
        snapshot?.itinerary?.progress.remaining?.meters
    }

    @Test func startsWithTheChosenItineraryAndStoresIt() async throws {
        let snapshot = try await service.start(sport: .run, itinerary: followed)

        #expect(snapshot.itinerary?.id == .fixture(3))
        #expect(snapshot.itinerary?.progress.status == .notSnapped)
        #expect(try await repository.load()?.itinerary?.id == .fixture(3))
    }

    @Test func theProgressFollowsThePositionDuringAPauseTooAndIsSaved() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)

        provider.send(fix(1, east: 0, north: 0))
        provider.send(fix(60, east: 200, north: 0))
        await snapshots.until { abs((remaining($0) ?? 0) - 1_400) < 2 }
        clock.value = start.addingTimeInterval(61)
        _ = try await service.pause()
        provider.send(fix(120, east: 400, north: 0))
        let paused = try #require(await snapshots.until { abs((remaining($0) ?? 0) - 1_200) < 2 })

        #expect(paused.pointCount == 2)
        let stored = try #require(try await repository.load()?.itinerary)
        #expect(abs(stored.progress.remaining!.meters - 1_200) < 2)
    }

    @Test func aStartedLoopDoesNotGoBackToItsStartOnRestore() async throws {
        var recording = Recording(sport: .run, startedAt: start)
        try await repository.create(recording)
        var itinerary = followed
        for (east, north) in [(0.0, 0.0), (400, 0), (400, 400), (0, 400), (0, 100)] {
            itinerary.progress.update(with: fix(1, east: east, north: north))
        }
        try await repository.saveItinerary(itinerary, of: recording.id)
        recording.pause(at: start.addingTimeInterval(600))
        try await repository.save(recording)
        let snapshots = await SnapshotWatcher(service)

        let restored = try #require(try await service.restore())
        #expect(abs(remaining(restored)! - 100) < 2)
        provider.send(fix(700, east: 0, north: 40))
        let snapshot = try #require(await snapshots.until { $0?.position != nil })

        #expect(abs(remaining(snapshot)! - 40) < 2)
    }

    @Test func removingTheItineraryForgetsIt() async throws {
        _ = try await service.start(sport: .ride, itinerary: followed)

        let snapshot = try #require(try await service.removeItinerary())

        #expect(snapshot.itinerary == nil)
        #expect(try await repository.load()?.itinerary == nil)
    }
}
