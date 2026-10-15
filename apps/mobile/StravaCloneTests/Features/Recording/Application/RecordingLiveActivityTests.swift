import Foundation
import Testing
@testable import StravaClone

/// The Live Activity of a Recording (ADR-031 §9), through the service with a simulated port:
/// rhythm of the updates, immediate updates on events, final content or removal at the end.
@MainActor
struct RecordingLiveActivityTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let origin = Coordinate(latitude: 45.764, longitude: 4.8357)
    private let provider = FakeLocationProvider()
    private let port = FakeRecordingLiveActivity()
    private let ticks = ManualTicks()
    private let clock: Locked<Date>
    private let repository: GRDBRecordingRepository
    private let updater: RecordingLiveActivityUpdater
    private let service: RecordingService
    private let running: Task<Void, Never>

    init() throws {
        let clock = Locked(start)
        self.clock = clock
        repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        let ticks = ticks
        updater = RecordingLiveActivityUpdater(port: port, now: { clock.value }, ticks: { ticks.stream() })
        service = RecordingService(
            locationProvider: provider,
            repository: repository,
            now: { clock.value },
            liveActivity: updater
        )
        let updater = updater
        running = Task { await updater.run() }
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// A fix `north` meters north of the origin, `seconds` after Start; the clock follows.
    private func fix(_ seconds: TimeInterval, north: Double) -> LocationSample {
        clock.value = at(seconds)
        return LocationSample(coordinate: origin.offset(northMeters: north), altitude: nil, horizontalAccuracy: 5, timestamp: at(seconds))
    }

    private func started() async {
        await port.until { $0.contains { if case .start = $0 { true } else { false } } }
    }

    @Test func startShowsTheRecordingAfterEndingWhatAPreviousRunLeft() async throws {
        _ = try await service.start(sport: .run)

        let calls = await port.until { $0.count == 2 }
        #expect(calls.first == .endAll)
        guard case let .start(content, staleDate) = calls.last else {
            Issue.record("no start: \(calls)")
            return
        }
        #expect(content.sport == .run)
        #expect(content.timerStart == start)
        #expect(content.pausedAt == nil)
        #expect(content.distance == .zero)
        #expect(content.itinerary == nil)
        #expect(staleDate == at(120))
    }

    @Test func positionsShowEveryFiveSecondsWithTheLatestStats() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)
        await started()

        provider.send(fix(1, north: 0))
        provider.send(fix(2, north: 3))
        provider.send(fix(3, north: 6))
        await snapshots.until { $0?.pointCount == 3 }
        clock.value = at(5)
        ticks.tick()
        let calls = await port.until { $0.count >= 3 }

        #expect(calls.count == 3) // one update for the three positions
        guard case let .update(content, staleDate) = calls.last else {
            Issue.record("no update: \(calls)")
            return
        }
        #expect(abs(content.distance.meters - 6) < 0.01)
        #expect(staleDate == at(125))

        provider.send(fix(6, north: 9))
        await snapshots.until { $0?.pointCount == 4 }
        clock.value = at(10)
        ticks.tick()
        await port.until { $0.count >= 4 }
        #expect(abs((port.contents.last?.distance.meters ?? 0) - 9) < 0.01)
    }

    @Test func aPauseAndAResumeShowAtOnceWithTheTimerFrozenThenShifted() async throws {
        _ = try await service.start(sport: .run)
        await started()

        clock.value = at(10)
        _ = try await service.pause()
        await port.until { $0.count >= 3 }
        #expect(port.contents.last?.pausedAt == at(10))
        #expect(port.contents.last?.timerStart == start)

        clock.value = at(40)
        _ = try await service.resume()
        await port.until { $0.count >= 4 }
        #expect(port.contents.last?.pausedAt == nil)
        #expect(port.contents.last?.timerStart == at(30)) // 30 s of Pause
        #expect(port.updateCount == 2)
    }

    @Test func anItineraryStateChangeAndItsRemovalShowAtOnce() async throws {
        let square = SyntheticTrack.through([(0, 0), (400, 0), (400, 400), (0, 400), (0, 0)])
        let itinerary = FollowedItinerary(id: .fixture(3), name: "Boucle", track: square, total: Distance(meters: 1_600))
        func fix(_ seconds: TimeInterval, east: Double, north: Double) -> LocationSample {
            clock.value = at(seconds)
            let coordinate = SyntheticTrack.point(east: east, north: north)
            return LocationSample(coordinate: coordinate, altitude: nil, horizontalAccuracy: 5, timestamp: at(seconds))
        }
        _ = try await service.start(sport: .run, itinerary: itinerary)
        await started()
        #expect(port.contents.first?.itinerary?.state == .notSnapped)
        #expect(port.contents.first?.itinerary?.remaining == nil)
        #expect(port.contents.first?.itinerary?.name == "Boucle")

        provider.send(fix(1, east: 0, north: 0))
        await port.until { $0.count >= 3 }
        #expect(port.contents.last?.itinerary?.state == .onTrack)
        #expect(port.contents.last?.itinerary?.remaining == Distance(meters: 1_600))

        provider.send(fix(20, east: 50, north: 0)) // still on the track: waits for the 5 s update
        provider.send(fix(40, east: 200, north: 200)) // middle of the square
        provider.send(fix(45, east: 200, north: 205))
        provider.send(fix(50, east: 200, north: 210)) // off for 3 points and 10 s: "Hors Itinéraire"
        await port.until { $0.count >= 4 }
        #expect(port.contents.last?.itinerary?.state == .offTrack)

        _ = try await service.removeItinerary()
        await port.until { $0.count >= 5 }
        #expect(port.contents.last?.itinerary == nil)
        #expect(await port.settled().count == 5)
    }

    /// Two minutes of running with 300 m covered, then the finish screen.
    private func finishedRun() async throws {
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)
        await started()
        provider.send(fix(1, north: 0))
        provider.send(fix(120, north: 300))
        await snapshots.until { $0?.pointCount == 2 }
        clock.value = at(121)
        _ = try await service.pause()
        _ = try await service.finish()
    }

    @Test func saveLeavesTheFinalContentAndStopsTheUpdates() async throws {
        try await finishedRun()

        try await service.save { _ in }
        let calls = await port.until { $0.last.map { if case .end = $0 { true } else { false } } ?? false }
        guard case let .end(final?) = calls.last else {
            Issue.record("no final content: \(calls)")
            return
        }
        #expect(final.isSaved)
        #expect(final.pausedAt == at(121))
        #expect(abs(final.distance.meters - 300) < 0.01)

        clock.value = at(130)
        ticks.tick()
        #expect(await port.settled().count == calls.count)
    }

    @Test func deleteRemovesTheLiveActivityAtOnce() async throws {
        try await finishedRun()

        try await service.delete()
        let calls = await port.until { $0.last == .end(final: nil) }
        #expect(calls.last == .end(final: nil))

        ticks.tick()
        #expect(await port.settled().count == calls.count)
    }

    @Test func aRefusedLiveActivityNeverBlocksTheRecordingAndIsAskedAgainLater() async throws {
        port.startSucceeds = false // Live Activities off in Settings, or the app in the background
        let snapshots = await SnapshotWatcher(service)
        _ = try await service.start(sport: .run)
        await started()

        provider.send(fix(1, north: 0))
        provider.send(fix(2, north: 3))
        _ = try #require(await snapshots.until { $0?.pointCount == 2 })
        #expect(try await repository.load()?.points.count == 2)
        clock.value = at(5)
        ticks.tick()
        var calls = await port.until { $0.count >= 3 }
        #expect(calls.dropFirst().allSatisfy { if case .start = $0 { true } else { false } })

        port.startSucceeds = true
        clock.value = at(10)
        ticks.tick()
        calls = await port.until { $0.count >= 4 }
        clock.value = at(15)
        ticks.tick()
        calls = await port.until { $0.count >= 5 }
        guard case .update = calls.last else {
            Issue.record("no update once started: \(calls)")
            return
        }
    }

    @Test func nothingIsSentWhileNothingChangesExceptToPushTheStaleDateBack() async throws {
        _ = try await service.start(sport: .run)
        await started()
        clock.value = at(10)
        _ = try await service.pause()
        await port.until { $0.count >= 3 }

        clock.value = at(15)
        ticks.tick()
        #expect(await port.settled().count == 3) // the same Pause: nothing new

        clock.value = at(70)
        ticks.tick()
        let calls = await port.until { $0.count >= 4 }
        guard case let .update(_, staleDate) = calls.last else {
            Issue.record("stale date not pushed back: \(calls)")
            return
        }
        #expect(staleDate == at(190))
    }

    @Test func atLaunchWhatAKilledRunLeftEndsBeforeTheResumedRecordingShows() async throws {
        let stored = Recording(sport: .walk, startedAt: start)
        try await repository.create(stored)
        _ = try await repository.append(fix(60, north: 80), to: stored.id)
        clock.value = at(600) // the app was dead meanwhile

        _ = try await service.restore(.openedByAthlete)
        let calls = await port.until { $0.count >= 2 }

        #expect(calls.first == .endAll)
        guard case let .start(content, _) = calls.dropFirst().first else {
            Issue.record("no start: \(calls)")
            return
        }
        #expect(content.sport == .walk)
        #expect(content.pausedAt == at(60)) // paused at the last point
    }
}
