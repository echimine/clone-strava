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
        try await repository.append(fix(1, north: 0), to: recording.id)
        try await repository.append(fix(2, north: 3), to: recording.id)
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
