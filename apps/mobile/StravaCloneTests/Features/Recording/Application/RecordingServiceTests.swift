import Foundation
import Testing
@testable import StravaClone

@MainActor
struct RecordingServiceTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let origin = Coordinate(latitude: 45.764, longitude: 4.8357)
    private let provider = FakeLocationProvider()
    private let clock: Locked<Date>
    private let repository: GRDBRecordingRepository
    private let service: RecordingService

    init() throws {
        let clock = Locked(start)
        self.clock = clock
        repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        service = RecordingService(locationProvider: provider, repository: repository, now: { clock.value })
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// A fix `north` meters north of the origin, `seconds` after Start; the clock follows.
    private func fix(_ seconds: TimeInterval, north: Double) -> LocationSample {
        clock.value = at(seconds)
        return LocationSample(coordinate: origin.offset(northMeters: north), altitude: nil, horizontalAccuracy: 5, timestamp: at(seconds))
    }

    @Test func startKeepsTheGPSRunningInTheBackgroundAndStoresTheRecording() async throws {
        let snapshot = try await service.start(sport: .ride)

        #expect(snapshot.recording.sport == .ride)
        #expect(snapshot.recording.startedAt == start)
        #expect(provider.beginBackgroundTrackingCount == 1)
        #expect(provider.isRecordingStreamActive)
        #expect(try await repository.load()?.recording == snapshot.recording)
    }

    @Test func onlyOneRecordingAtATime() async throws {
        _ = try await service.start(sport: .run)

        await #expect(throws: RecordingRepositoryError.alreadyExists) {
            _ = try await service.start(sport: .walk)
        }
    }

    @Test func pointsAreWrittenAsTheyArriveAndMakeTheDistance() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)

        provider.send(fix(1, north: 0))
        provider.send(fix(2, north: 3))
        provider.send(fix(3, north: 6))
        let snapshot = try #require(await snapshots.until { $0?.pointCount == 3 })

        #expect(abs(snapshot.distance.meters - 6) < 0.01)
        #expect(snapshot.trace.count == 3)
        #expect(try await repository.load()?.points.count == 3)
    }

    @Test func aStalePositionFromBeforeStartIsNotWritten() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)

        provider.send(fix(-30, north: 0))
        provider.send(fix(1, north: 3))
        let snapshot = try #require(await snapshots.until { $0?.position?.timestamp == at(1) })

        #expect(snapshot.pointCount == 1)
        #expect(try await repository.load()?.points.count == 1)
    }

    @Test func aPauseKeepsTheGPSButWritesNothing() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)
        provider.send(fix(1, north: 0))
        await snapshots.until { $0?.pointCount == 1 }

        clock.value = at(2)
        let paused = try #require(try await service.pause())
        provider.send(fix(30, north: 400))
        let during = try #require(await snapshots.until { $0?.position?.timestamp == at(30) })

        #expect(paused.recording.phase == .paused)
        #expect(provider.isRecordingStreamActive)
        #expect(provider.endBackgroundTrackingCount == 0)
        #expect(during.pointCount == 1)
        #expect(during.stats(at: at(30)).currentSpeedMs == nil)
        #expect(during.stats(at: at(30)).elapsed == .seconds(2))
        #expect(try await repository.load()?.points.count == 1)
    }

    @Test func theMoveDuringAPauseNeverCounts() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)
        provider.send(fix(1, north: 0))
        provider.send(fix(2, north: 3))
        await snapshots.until { $0?.pointCount == 2 }
        clock.value = at(3)
        _ = try await service.pause()

        clock.value = at(600)
        let resumed = try #require(try await service.resume())
        provider.send(fix(601, north: 5_000))
        provider.send(fix(602, north: 5_003))
        let snapshot = try #require(await snapshots.until { $0?.pointCount == 4 })

        #expect(resumed.recording.pauses == [RecordingPause(start: at(3), end: at(600))])
        #expect(abs(snapshot.distance.meters - 6) < 0.01)
        #expect(snapshot.stats(at: at(602)).elapsed == .seconds(5))
        #expect(try await repository.load()?.recording.pauses.count == 1)
    }

    @Test func finishOpensTheFinishScreenAndResumeReturnsToThePause() async throws {
        _ = try await service.start(sport: .walk)
        clock.value = at(100)

        #expect(try await service.finish()?.recording.phase == .active) // only from a Pause
        _ = try await service.pause()
        let finishing = try #require(try await service.finish())
        #expect(finishing.recording.phase == .finishing)
        #expect(finishing.recording.endedAt == at(100))
        #expect(try await repository.load()?.recording.phase == .finishing)

        let back = try #require(try await service.reopen())
        #expect(back.recording.phase == .paused)
    }

    @Test func deleteLeavesNothingAndReleasesTheGPS() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)
        provider.send(fix(1, north: 0))
        await snapshots.until { $0?.pointCount == 1 }
        clock.value = at(2)
        _ = try await service.pause()
        _ = try await service.resume()
        _ = try await service.pause()
        _ = try await service.finish()

        try await service.delete()
        await snapshots.until { $0 == nil }
        while provider.updateSubscriberCount > 0 {
            await Task.yield()
        }

        #expect(try await repository.load() == nil)
        #expect(provider.endBackgroundTrackingCount == 1)
        #expect(!provider.isUpdating)
        // A new Recording can start.
        #expect(try await service.start(sport: .ride).pointCount == 0)
    }

    @Test func restoreReloadsTheStoredRecordingAndItsDistance() async throws {
        var recording = Recording(sport: .run, startedAt: start)
        try await repository.create(recording)
        try await repository.append(fix(1, north: 0), to: recording.id)
        try await repository.append(fix(2, north: 3), to: recording.id)
        recording.pause(at: at(3))
        try await repository.save(recording)

        let snapshot = try #require(try await service.restore())

        #expect(snapshot.recording == recording)
        #expect(snapshot.pointCount == 2)
        #expect(abs(snapshot.distance.meters - 3) < 0.01)
        #expect(provider.beginBackgroundTrackingCount == 1)
        #expect(provider.isRecordingStreamActive)
    }

    @Test func restoreWithoutARecordingDoesNothing() async throws {
        #expect(try await service.restore() == nil)
        #expect(provider.beginBackgroundTrackingCount == 0)
        #expect(!provider.isUpdating)
    }
}

/// Follows `RecordingService.snapshots()` so a test can wait for a given state.
@MainActor
final class SnapshotWatcher {
    /// `.some(nil)` once the service reported no Recording.
    private(set) var latest: RecordingSnapshot??
    private var task: Task<Void, Never>?

    init(_ service: RecordingService) async {
        let stream = await service.snapshots()
        task = Task { [weak self] in
            for await snapshot in stream {
                self?.latest = .some(snapshot)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    /// Waits for a state matching `predicate`, returns its Recording.
    @discardableResult
    func until(_ predicate: (RecordingSnapshot?) -> Bool) async -> RecordingSnapshot? {
        while true {
            if let latest, predicate(latest) { return latest }
            await Task.yield()
        }
    }
}
