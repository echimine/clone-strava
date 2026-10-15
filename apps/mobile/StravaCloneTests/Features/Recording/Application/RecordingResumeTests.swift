import Foundation
import Testing
@testable import StravaClone

/// ADR-031 §3, §10: a Recording is never lost when the app is killed or crashes.
@MainActor
struct RecordingResumeTests {
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

    private func fix(_ seconds: TimeInterval, north: Double) -> LocationSample {
        LocationSample(coordinate: origin.offset(northMeters: north), altitude: nil, horizontalAccuracy: 5, timestamp: at(seconds))
    }

    /// An `active` Recording left on disk by a killed app, with points written up to 2 s.
    private func storeActiveRecording() async throws -> Recording {
        let recording = Recording(sport: .run, startedAt: start)
        try await repository.create(recording)
        _ = try await repository.append(fix(1, north: 0), to: recording.id)
        _ = try await repository.append(fix(2, north: 3), to: recording.id)
        return recording
    }

    @Test func anActiveRecordingOpenedByTheAthleteReopensPausedAtTheLastPoint() async throws {
        _ = try await storeActiveRecording()
        clock.value = at(900) // the app was dead for 15 min

        let snapshot = try #require(try await service.restore(.openedByAthlete))

        #expect(snapshot.recording.phase == .paused)
        #expect(snapshot.recording.currentPauseStartedAt == at(2))
        #expect(snapshot.stats(at: at(900)).elapsed == .seconds(2))
        #expect(abs(snapshot.distance.meters - 3) < 0.01)
        #expect(try await repository.load()?.recording.phase == .paused)
        #expect(provider.beginBackgroundTrackingCount == 1)
        #expect(provider.isRecordingStreamActive)
    }

    @Test func aPointAfterTheReopeningIsNotWrittenUntilTheAthleteResumes() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await storeActiveRecording()
        clock.value = at(900)
        _ = try await service.restore(.openedByAthlete)

        provider.send(fix(901, north: 2_000))
        let snapshot = try #require(await snapshots.until { $0?.position?.timestamp == at(901) })

        #expect(snapshot.pointCount == 2)
        #expect(try await repository.load()?.points.count == 2)
    }

    @Test func aBackgroundRelaunchGoesOnInTheSavedPhaseWithoutAPause() async throws {
        let snapshots = await SnapshotWatcher(service)
        let recording = try await storeActiveRecording()
        clock.value = at(60)

        let restored = try #require(try await service.restore(.relaunchedInBackground))
        clock.value = at(61)
        provider.send(fix(61, north: 6))
        let snapshot = try #require(await snapshots.until { $0?.pointCount == 3 })

        #expect(restored.recording == recording)
        #expect(snapshot.recording.phase == .active)
        #expect(snapshot.recording.pauses.isEmpty)
        #expect(snapshot.stats(at: at(61)).elapsed == .seconds(61))
        #expect(try await repository.load()?.points.count == 3)
    }

    @Test(arguments: [RecordingLaunch.openedByAthlete, .relaunchedInBackground])
    func aPausedRecordingStaysPaused(after launch: RecordingLaunch) async throws {
        var recording = try await storeActiveRecording()
        recording.pause(at: at(10))
        try await repository.save(recording)
        clock.value = at(900)

        let snapshot = try #require(try await service.restore(launch))

        #expect(snapshot.recording == recording)
        #expect(snapshot.recording.currentPauseStartedAt == at(10))
    }

    @Test(arguments: [RecordingLaunch.openedByAthlete, .relaunchedInBackground])
    func aFinishingRecordingReopensTheFinishScreen(after launch: RecordingLaunch) async throws {
        var recording = try await storeActiveRecording()
        recording.pause(at: at(10))
        recording.finish()
        try await repository.save(recording)
        clock.value = at(900)

        let snapshot = try #require(try await service.restore(launch))

        #expect(snapshot.recording.phase == .finishing)
        #expect(snapshot.recording.endedAt == at(10))
    }

    @Test func anActiveRecordingWithoutPointsSinceTheLastResumePausesAtThatResume() async throws {
        var recording = try await storeActiveRecording()
        recording.pause(at: at(10))
        recording.resume(at: at(40))
        try await repository.save(recording)
        clock.value = at(900)

        let snapshot = try #require(try await service.restore(.openedByAthlete))

        #expect(snapshot.recording.currentPauseStartedAt == at(40))
        #expect(snapshot.stats(at: at(900)).elapsed == .seconds(10))
    }

    @Test func concurrentRestoresPickTheRecordingUpOnce() async throws {
        _ = try await storeActiveRecording()
        clock.value = at(900)

        async let first = service.restore(.openedByAthlete)
        async let second = service.restore(.openedByAthlete)
        let (a, b) = try await (first, second)

        #expect(a == b)
        #expect(a?.recording.currentPauseStartedAt == at(2))
        #expect(provider.beginBackgroundTrackingCount == 1)
    }
}

/// ADR-031 §10: a failed write keeps the points in memory; the Recording never stops by itself.
@MainActor
struct RecordingWriteFailureTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let origin = Coordinate(latitude: 45.764, longitude: 4.8357)
    private let provider = FakeLocationProvider()
    private let clock: Locked<Date>
    private let repository: FlakyRecordingRepository
    private let service: RecordingService

    init() throws {
        let clock = Locked(start)
        self.clock = clock
        repository = FlakyRecordingRepository(GRDBRecordingRepository(database: try AppDatabase.inMemory()))
        service = RecordingService(locationProvider: provider, repository: repository, now: { clock.value })
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// A fix `seconds` after Start, `north` meters north of the origin; the clock follows.
    private func fix(_ seconds: TimeInterval, north: Double) -> LocationSample {
        clock.value = at(seconds)
        return LocationSample(coordinate: origin.offset(northMeters: north), altitude: nil, horizontalAccuracy: 5, timestamp: at(seconds))
    }

    @Test func pointsThatCouldNotBeWrittenAreWrittenOnceTheDiskWorksAgain() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)
        provider.send(fix(1, north: 0))
        await snapshots.until { $0?.pointCount == 1 }

        repository.failsWrites.value = true
        provider.send(fix(2, north: 3))
        provider.send(fix(3, north: 6))
        let failing = try #require(await snapshots.until { $0?.pointCount == 3 })
        #expect(abs(failing.distance.meters - 6) < 0.01)
        #expect(failing.recording.phase == .active)
        #expect(try await repository.load()?.points.count == 1)

        repository.failsWrites.value = false
        provider.send(fix(4, north: 9))
        await snapshots.until { $0?.pointCount == 4 }

        let written = try #require(try await repository.load()).points.map(\.timestamp)
        #expect(written == [at(1), at(2), at(3), at(4)])
    }

    @Test func theWarningShowsAfter30SecondsOfFailureAndGoesAwayOnceWritten() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)
        repository.failsWrites.value = true

        provider.send(fix(1, north: 0))
        provider.send(fix(30, north: 3))
        let before = try #require(await snapshots.until { $0?.pointCount == 2 })
        #expect(!before.isTraceWriteFailing)

        provider.send(fix(31, north: 6))
        let after = try #require(await snapshots.until { $0?.pointCount == 3 })
        #expect(after.isTraceWriteFailing)

        repository.failsWrites.value = false
        provider.send(fix(32, north: 9))
        let recovered = try #require(await snapshots.until { $0?.pointCount == 4 })
        #expect(!recovered.isTraceWriteFailing)
        #expect(try await repository.load()?.points.count == 4)
    }
}

/// A `RecordingRepository` whose point writes fail on demand, as a full disk would.
final class FlakyRecordingRepository: RecordingRepository {
    struct DiskFull: Error {}

    let failsWrites = Locked(false)
    private let base: GRDBRecordingRepository

    init(_ base: GRDBRecordingRepository) {
        self.base = base
    }

    func load() async throws -> StoredRecording? { try await base.load() }
    func create(_ recording: Recording) async throws { try await base.create(recording) }
    func save(_ recording: Recording) async throws { try await base.save(recording) }
    func delete(_ id: ActivityID) async throws { try await base.delete(id) }

    func append(_ point: LocationSample, to id: ActivityID) async throws -> Bool {
        if failsWrites.value { throw DiskFull() }
        return try await base.append(point, to: id)
    }
}
