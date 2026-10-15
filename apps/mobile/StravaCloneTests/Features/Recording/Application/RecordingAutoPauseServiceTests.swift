import Foundation
import Testing
@testable import StravaClone

/// The automatic Pause in a running Recording (ADR-031 §4, §10).
@MainActor
struct RecordingAutoPauseServiceTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let origin = Coordinate(latitude: 45.764, longitude: 4.8357)
    private let provider = FakeLocationProvider()
    private let motion = FakeMotionActivityProvider()
    private let feedback = FakeAutoPauseFeedback()
    private let clock: Locked<Date>
    private let repository: GRDBRecordingRepository
    private let service: RecordingService

    init() throws {
        let clock = Locked(start)
        self.clock = clock
        repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        service = RecordingService(
            locationProvider: provider,
            repository: repository,
            now: { clock.value },
            motionProvider: motion,
            autoPauseFeedback: feedback
        )
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// One fix per second from `from` to `to` included, `north(second)` meters north of the origin.
    private func send(_ seconds: ClosedRange<Int>, speed: Double?, north: (Int) -> Double) {
        for second in seconds {
            clock.value = at(TimeInterval(second))
            provider.send(LocationSample(
                coordinate: origin.offset(northMeters: north(second)),
                altitude: nil,
                horizontalAccuracy: 5,
                speed: speed,
                timestamp: at(TimeInterval(second))
            ))
        }
    }

    /// Rides 30 s at 8 m/s, then stands still from second 31 to `standUntil` at 240 m.
    private func rideThenStop(standUntil: Int = 60) {
        send(1...30, speed: 8) { Double($0) * 8 }
        send(31...standUntil, speed: 0) { _ in 240 }
    }

    @Test func aStopOnARidePausesByItselfAndTheDepartureResumesIt() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .ride, autoPause: true)

        rideThenStop()
        let paused = try #require(await snapshots.until { $0?.recording.isAutomaticallyPaused == true && $0?.position?.timestamp == at(60) })
        #expect(paused.recording.currentPauseStartedAt == at(40))
        #expect(paused.pointCount == 40)

        send(61...64, speed: 6) { 240 + Double($0 - 60) * 6 }
        // The Pause ends at the actual departure; the points held since are written.
        let resumed = try #require(await snapshots.until { $0?.recording.phase == .active && $0?.pointCount == 45 })

        #expect(resumed.recording.pauses == [RecordingPause(start: at(40), end: at(60))])
        #expect(abs(resumed.distance.meters - 256) < 0.1)
        #expect(resumed.stats(at: at(64)).elapsed == .seconds(44))
        let stored = try #require(try await repository.load())
        #expect(stored.points.count == 45)
        #expect(stored.recording.pauses.count == 1)
        #expect(feedback.events == [.started, .ended])
    }

    @Test func aManualPauseNeverResumesByItself() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .ride, autoPause: true)
        send(1...10, speed: 8) { Double($0) * 8 }
        await snapshots.until { $0?.pointCount == 10 }

        _ = try await service.pause()
        send(11...40, speed: 8) { Double($0) * 8 }
        let snapshot = try #require(await snapshots.until { $0?.position?.timestamp == at(40) })

        #expect(snapshot.recording.phase == .paused)
        #expect(snapshot.recording.currentPauseKind == .manual)
        #expect(feedback.events.isEmpty)
    }

    @Test func afterAManualResumeTheRulesKeepWatching() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .ride, autoPause: true)
        send(1...10, speed: 8) { Double($0) * 8 }
        await snapshots.until { $0?.pointCount == 10 }
        _ = try await service.pause()
        clock.value = at(20)
        _ = try await service.resume()

        send(21...30, speed: 8) { Double($0) * 8 }
        send(31...45, speed: 0) { _ in 240 }
        let snapshot = try #require(await snapshots.until { $0?.position?.timestamp == at(45) })

        #expect(snapshot.recording.isAutomaticallyPaused)
        #expect(snapshot.recording.currentPauseStartedAt == at(40))
    }

    @Test func anAutomaticPauseRestoredAfterARelaunchStaysAutomaticAndResumesByItself() async throws {
        var recording = Recording(sport: .ride, startedAt: start, autoPauseEnabled: true)
        try await repository.create(recording)
        let stop = origin.offset(northMeters: 240)
        recording.pause(at: at(40), kind: .automatic, position: stop)
        try await repository.save(recording)
        let snapshots = await SnapshotWatcher(service)

        let restored = try #require(try await service.restore())
        #expect(restored.recording.isAutomaticallyPaused)

        clock.value = at(600)
        send(600...604, speed: 6) { 240 + Double($0 - 600) * 6 }
        let resumed = try #require(await snapshots.until { $0?.recording.phase == .active && $0?.position?.timestamp == at(604) })

        #expect(resumed.recording.pauses == [RecordingPause(start: at(40), end: at(600))])
    }

    @Test func switchingOffDuringAnAutomaticPauseLeavesTheRecordingPaused() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .ride, autoPause: true)
        rideThenStop(standUntil: 45)
        await snapshots.until { $0?.recording.isAutomaticallyPaused == true && $0?.position?.timestamp == at(45) }

        let switchedOff = try #require(try await service.setAutoPause(false))
        send(46...60, speed: 8) { 240 + Double($0 - 45) * 8 }
        let snapshot = try #require(await snapshots.until { $0?.position?.timestamp == at(60) })

        #expect(!switchedOff.recording.autoPauseEnabled)
        #expect(snapshot.recording.phase == .paused)
        #expect(try await repository.load()?.recording.autoPauseEnabled == false)
    }

    @Test func withoutTheSwitchARideNeverPausesByItself() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .ride)

        rideThenStop()
        let snapshot = try #require(await snapshots.until { $0?.position?.timestamp == at(60) })

        #expect(snapshot.recording.phase == .active)
        #expect(snapshot.pointCount == 60)
    }

    @Test func aRunPausesOnCoreMotionAndResumesWhenRunningAgain() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run, autoPause: true)
        while motion.subscriberCount == 0 {
            await Task.yield()
        }

        motion.send(MotionReading(activity: .running, confidence: .high, startDate: at(0)))
        send(1...20, speed: 3) { Double($0) * 3 }
        motion.send(MotionReading(activity: .stationary, confidence: .high, startDate: at(20)))
        send(21...30, speed: 0) { _ in 60 }
        let paused = try #require(await snapshots.until { $0?.recording.isAutomaticallyPaused == true })
        let pauseStart = try #require(paused.recording.currentPauseStartedAt)
        #expect(pauseStart >= at(25) && pauseStart <= at(30))

        await snapshots.until { $0?.position?.timestamp == at(30) }
        motion.send(MotionReading(activity: .running, confidence: .high, startDate: at(31)))
        let resumed = try #require(await snapshots.until { $0?.recording.phase == .active })
        #expect(resumed.recording.pauses.last?.end == at(31))
    }
}
