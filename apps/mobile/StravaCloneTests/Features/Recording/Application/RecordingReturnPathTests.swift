import Foundation
import Testing
@testable import StravaClone

/// Return path (ADR-031 §7) through the service, with a simulated router, clock and network:
/// when it is asked, where it leads, how often, and what happens when the router fails.
@MainActor
struct RecordingReturnPathTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let provider = FakeLocationProvider()
    private let router = FakeReturnPathRouter()
    private let network = FakeConnectivity()
    /// The 30 s retry timer, driven by the test.
    private let sleeper = ManualSleeper()
    private let clock: Locked<Date>
    private let repository: GRDBRecordingRepository
    private let service: RecordingService
    /// 1 km straight east.
    private let line = SyntheticTrack.through([(0, 0), (1_000, 0)])

    init() throws {
        let clock = Locked(start)
        self.clock = clock
        repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        service = Self.makeService(
            provider: provider,
            repository: repository,
            router: router,
            network: network,
            clock: clock,
            sleep: sleeper.sleep
        )
    }

    static func makeService(
        provider: FakeLocationProvider,
        repository: GRDBRecordingRepository,
        router: FakeReturnPathRouter,
        network: FakeConnectivity,
        clock: Locked<Date>,
        sleep: @escaping @Sendable (Duration) async throws -> Void = ManualSleeper().sleep
    ) -> RecordingService {
        RecordingService(
            locationProvider: provider,
            repository: repository,
            now: { clock.value },
            returnPathRouter: router,
            connectivity: { network.stream() },
            sleep: sleep
        )
    }

    private var followed: FollowedItinerary {
        FollowedItinerary(id: .fixture(7), name: "Tout droit", track: line, total: Distance(meters: 1_000))
    }

    private func point(_ east: Double, _ north: Double) -> Coordinate {
        SyntheticTrack.point(east: east, north: north)
    }

    /// Sends a fix `seconds` after Start (the clock follows) and waits until the service handled it.
    @discardableResult
    private func send(
        _ seconds: TimeInterval,
        _ east: Double,
        _ north: Double,
        accuracy: Double = 5,
        course: Double? = nil,
        to watcher: ReturnPathWatcher
    ) async -> RecordingSnapshot? {
        let time = start.addingTimeInterval(seconds)
        clock.value = time
        provider.send(LocationSample(
            coordinate: point(east, north),
            altitude: nil,
            horizontalAccuracy: accuracy,
            course: course,
            timestamp: time
        ))
        return await watcher.until { $0?.position?.timestamp == time }
    }

    /// On the track at 0 and 100 m, then off it 100 m north from 20 s on, one fix every 5 s
    /// until `seconds`.
    private func leaveTheTrack(until seconds: TimeInterval, watcher: ReturnPathWatcher) async {
        await send(1, 0, 0, to: watcher)
        await send(10, 100, 0, to: watcher)
        for time in stride(from: 20.0, through: seconds, by: 5) {
            await send(time, 100 + (time - 20), 100, course: 90, to: watcher)
        }
    }

    private func expectNear(_ coordinate: Coordinate?, _ east: Double, _ north: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let coordinate else {
            Issue.record("no coordinate", sourceLocation: sourceLocation)
            return
        }
        #expect(coordinate.distance(to: point(east, north)).meters < 2, sourceLocation: sourceLocation)
    }

    @Test func threeAccuratePointsOver10SecondsOffTheTrackAskAReturnPath() async throws {
        let watcher = await ReturnPathWatcher(service)
        await router.hold()
        _ = try await service.start(sport: .run, itinerary: followed)
        await send(1, 0, 0, to: watcher)
        await send(10, 100, 0, to: watcher)

        await send(20, 100, 100, course: 90, to: watcher)
        await send(22, 102, 100, accuracy: 80, to: watcher) // inaccurate: does not count
        await send(25, 105, 100, course: 90, to: watcher)
        let tooSoon = await send(29, 109, 100, course: 90, to: watcher) // 3 points, 9 s
        #expect(await router.calls.isEmpty)
        #expect(tooSoon?.itinerary?.state == .onTrack)

        let off = await send(31, 111, 100, course: 90, to: watcher)
        #expect(off?.itinerary?.state == .offTrack)
        let call = try #require(await router.waitForCalls(1).first)
        expectNear(call.position, 111, 100)
        expectNear(call.destination, 111, 0)
        #expect(call.profile == .walking)
        #expect(call.bearing == Bearing(degrees: 90, tolerance: 45))
        await router.release()
    }

    @Test func theReturnPathShowsAndTheDistanceLeftFollowsTheAthleteAlongIt() async throws {
        await router.answer { position, destination in
            RoutedReturnPath(path: [position, destination], distance: Distance(meters: 120))
        }
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .ride, itinerary: followed)
        await leaveTheTrack(until: 30, watcher: watcher)

        let shown = try #require(await watcher.until { $0?.itinerary?.returnPath != nil }?.itinerary)
        #expect(shown.state == .returnPath)
        #expect(await router.calls.first?.profile == .cycling)
        // 120 m of Return path from (110, 100) to (110, 0), then the 890 m of the Itinerary left.
        #expect(abs(shown.remaining!.meters - 1_010) < 2)
        #expect(abs(shown.progress.fraction - 0.1) < 0.01)

        // 40 % along the Return path: 60 % of its 120 m left.
        let along = try #require(await send(35, 110, 60, to: watcher)?.itinerary)
        #expect(along.state == .returnPath)
        #expect(abs(along.remaining!.meters - 962) < 3)
        #expect(abs(along.progress.fraction - 0.1) < 0.01)
    }

    @Test func reSnappingClearsTheReturnPathAndCancelsTheRequestInFlight() async throws {
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)
        await leaveTheTrack(until: 30, watcher: watcher)
        await watcher.until { $0?.itinerary?.returnPath != nil }
        #expect(try await repository.load()?.itinerary?.returnPath != nil)

        await router.hold()
        await send(35, 300, 120, to: watcher) // leaves the Return path too
        await send(40, 310, 120, to: watcher)
        await send(61, 320, 120, to: watcher)
        await router.waitForCalls(2)
        let back = try #require(await send(62, 330, 5, to: watcher)?.itinerary)
        await router.release()

        #expect(back.state == .onTrack)
        #expect(back.returnPath == nil)
        let settled = await send(63, 335, 5, to: watcher)
        #expect(settled?.itinerary?.returnPath == nil)
        #expect(try await repository.load()?.itinerary?.returnPath == nil)
    }

    @Test func beforeTheFirstSnapTheReturnPathLeadsToTheStart() async throws {
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .walk, itinerary: followed)
        for time in [1.0, 6, 11] {
            await send(time, 300, -400, to: watcher)
        }

        let call = try #require(await router.waitForCalls(1).first)
        expectNear(call.destination, 0, 0)
        let shown = try #require(await watcher.until { $0?.itinerary?.returnPath != nil }?.itinerary)
        // 500 m as the crow flies, 600 m by the fake router, then the whole Itinerary.
        #expect(abs(shown.remaining!.meters - 1_600) < 3)
    }

    @Test func worksDuringAPauseToo() async throws {
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)
        await send(1, 0, 0, to: watcher)
        await send(10, 100, 0, to: watcher)
        clock.value = start.addingTimeInterval(15)
        _ = try await service.pause()

        for time in [20.0, 25, 30] {
            await send(time, 100, 100, to: watcher)
        }

        #expect(await router.waitForCalls(1).count == 1)
        #expect(await watcher.until { $0?.itinerary?.returnPath != nil }?.recording.isPaused == true)
    }

    @Test func noRouteStaysOffTheItineraryUntilTheNextDeparture() async throws {
        await router.fail(with: .noPath)
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)

        await leaveTheTrack(until: 120, watcher: watcher)
        #expect(await router.calls.count == 1)
        #expect(watcher.latest??.itinerary?.state == .offTrack)

        await send(125, 300, 5, to: watcher) // back on the track
        for time in [130.0, 135, 140] {
            await send(time, 320, 100, to: watcher)
        }
        #expect(await router.waitForCalls(2).count == 2)
    }

    @Test func aSaturatedRouterIsAskedAgainAfter30Seconds() async throws {
        await router.fail(with: .rateLimited)
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)

        await leaveTheTrack(until: 55, watcher: watcher)
        await send(59, 140, 100, to: watcher)
        #expect(await router.calls.count == 1)
        #expect(watcher.latest??.itinerary?.state == .offTrack)

        await send(60, 141, 100, to: watcher)
        #expect(await router.waitForCalls(2).count == 2)
    }

    /// The athlete stops after leaving the track: no fix comes, the retry leaves on its own.
    @Test func aFailedRequestIsAskedAgainAfter30SecondsEvenWithoutANewFix() async throws {
        await router.fail(with: .temporary)
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)
        await leaveTheTrack(until: 30, watcher: watcher)
        #expect(await router.waitForCalls(1).count == 1)
        #expect(await eventually { sleeper.waiting == 1 })
        #expect(sleeper.requested.last == .seconds(30))

        await router.answer(with: FakeReturnPathRouter.straight)
        clock.value = start.addingTimeInterval(60)
        sleeper.wakeAll()

        let calls = await router.waitForCalls(2)
        #expect(calls.count == 2)
        expectNear(calls.last?.position, 110, 100)
        await watcher.until { $0?.itinerary?.returnPath != nil }
    }

    @Test func reSnappingCancelsTheRetry() async throws {
        await router.fail(with: .temporary)
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)
        await leaveTheTrack(until: 30, watcher: watcher)
        #expect(await eventually { sleeper.waiting == 1 })

        await send(35, 120, 5, to: watcher) // back on the track

        #expect(sleeper.waiting == 0)
    }

    @Test func removingTheItineraryCancelsTheRetry() async throws {
        await router.fail(with: .temporary)
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)
        await leaveTheTrack(until: 30, watcher: watcher)
        #expect(await eventually { sleeper.waiting == 1 })

        _ = try await service.removeItinerary()

        #expect(sleeper.waiting == 0)
    }

    @Test func atMostFiveRequestsPerDepartureThenOfflineModeUntilReSnapping() async throws {
        await router.fail(with: .temporary)
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)

        await leaveTheTrack(until: 300, watcher: watcher)
        #expect(await router.calls.count == 5)
        #expect(watcher.latest??.itinerary?.state == .offTrack)

        await send(305, 400, 5, to: watcher) // back on the track: a new departure, a new count
        for time in [310.0, 315, 320] {
            await send(time, 420, 100, to: watcher)
        }
        #expect(await router.waitForCalls(6).count == 6)
    }

    @Test func leavingTheReturnPathAsksANewOneNoSoonerThan30SecondsAfterThePrevious() async throws {
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)
        await leaveTheTrack(until: 30, watcher: watcher)
        let first = try #require(await watcher.until { $0?.itinerary?.returnPath != nil }?.itinerary?.returnPath)

        // More than 50 m from the Return path and from the track for 3 points over 10 s.
        for time in [35.0, 40, 45, 50, 55] {
            await send(time, 250 + time, 120, to: watcher)
        }
        #expect(await router.calls.count == 1)
        #expect(watcher.latest??.itinerary?.returnPath == first) // kept until the next one

        await send(60, 310, 120, to: watcher)
        let calls = await router.waitForCalls(2)
        #expect(calls.count == 2)
        expectNear(calls.last?.position, 310, 120)
        let next = await watcher.until { $0?.itinerary?.returnPath != first }
        expectNear(next?.itinerary?.returnPath?.returnPoint.coordinate, 310, 0)
    }

    @Test func withoutNetworkItWaitsForTheNetworkAndKeepsAReturnPathAlreadyShown() async throws {
        network.set(false)
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)

        await leaveTheTrack(until: 40, watcher: watcher)
        #expect(await router.calls.isEmpty)
        #expect(watcher.latest??.itinerary?.state == .offTrack)

        network.set(true)
        #expect(await router.waitForCalls(1).count == 1)
        await watcher.until { $0?.itinerary?.returnPath != nil }

        network.set(false)
        let offline = await send(45, 125, 100, to: watcher)
        #expect(offline?.itinerary?.state == .returnPath)
    }

    @Test func onResumeTheSavedReturnPathShowsWithoutANewRequest() async throws {
        let watcher = await ReturnPathWatcher(service)
        _ = try await service.start(sport: .run, itinerary: followed)
        await leaveTheTrack(until: 30, watcher: watcher)
        let shown = try #require(await watcher.until { $0?.itinerary?.returnPath != nil }?.itinerary)

        let reopenedRouter = FakeReturnPathRouter()
        let reopened = Self.makeService(
            provider: FakeLocationProvider(),
            repository: repository,
            router: reopenedRouter,
            network: FakeConnectivity(),
            clock: clock
        )
        let restored = try #require(try await reopened.restore()?.itinerary)

        #expect(restored.state == .returnPath)
        #expect(restored.returnPath?.path.count == shown.returnPath?.path.count)
        #expect(restored.returnPath?.returnPoint == shown.returnPath?.returnPoint)
        #expect(abs(restored.remaining!.meters - shown.remaining!.meters) < 1)
        #expect(await reopenedRouter.calls.isEmpty)
    }
}

/// Simulated `NWPathMonitor`: `true` while a network route exists.
final class FakeConnectivity: Sendable {
    private let continuations = Locked<[AsyncStream<Bool>.Continuation]>([])
    private let current = Locked(true)

    func stream() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        continuation.yield(current.value)
        continuations.value.append(continuation)
        return stream
    }

    func set(_ isConnected: Bool) {
        current.value = isConnected
        continuations.value.forEach { $0.yield(isConnected) }
    }
}

/// The service's latest snapshot, with waits that give up after a deadline (a red test must
/// not hang the run).
@MainActor
final class ReturnPathWatcher {
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

    @discardableResult
    func until(timeout: Duration = .seconds(2), _ predicate: (RecordingSnapshot?) -> Bool) async -> RecordingSnapshot? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let latest, predicate(latest) { return latest }
            await Task.yield()
        }
        Issue.record("timed out waiting for a snapshot")
        return latest ?? nil
    }
}
