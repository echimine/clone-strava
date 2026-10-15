import Foundation
import Testing
@testable import StravaClone

/// Save on the finish screen (ADR-031 §11): one transaction turns the Recording into a local
/// Activity in `recorded` and queues `create_activity`; the Record tab returns to the
/// pre-start screen. Real GRDB in memory for both the Recording and the local Activities.
@MainActor
struct RecordingSaveTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let provider = FakeLocationProvider()
    private let preferences = InMemoryRecordingPreferences()
    private let repository: GRDBRecordingRepository
    private let activities: GRDBLocalActivityStore
    private let service: RecordingService
    private let paris = TimeZone(identifier: "Europe/Paris")!

    init() throws {
        let database = try AppDatabase.inMemory()
        repository = GRDBRecordingRepository(database: database)
        activities = GRDBLocalActivityStore(database: database)
        service = RecordingService(locationProvider: provider, repository: repository)
    }

    private func makeStore(defaultVisibility: ActivityVisibility = .public) -> RecordingStore {
        RecordingStore(
            service: service,
            preferences: preferences,
            itineraries: FakeItineraryCacheReader(),
            ensureFullAccuracy: { true },
            saveRecording: SaveRecording(service: service, activities: GRDBRecordingSaver(activities: activities), timeZone: paris),
            defaultVisibility: { defaultVisibility }
        )
    }

    private func until(_ store: RecordingStore, _ condition: (RecordingStore) -> Bool) async {
        while !condition(store) {
            await Task.yield()
        }
    }

    private func sample(_ seconds: TimeInterval, north: Double) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: 45.764, longitude: 4.8357).offset(northMeters: north),
            altitude: nil,
            horizontalAccuracy: 5,
            timestamp: start.addingTimeInterval(seconds)
        )
    }

    /// A ride of 10 min with a 2-min Pause, finished at 12 min: on the finish screen.
    private func finishedRide() async throws -> Recording {
        var recording = Recording(sport: .ride, startedAt: start)
        try await repository.create(recording)
        try await repository.append(sample(0, north: 0), to: recording.id)
        try await repository.append(sample(240, north: 1_000), to: recording.id)
        recording.pause(at: start.addingTimeInterval(240))
        recording.resume(at: start.addingTimeInterval(360))
        try await repository.save(recording)
        try await repository.append(sample(720, north: 3_000), to: recording.id)
        recording.pause(at: start.addingTimeInterval(720))
        recording.finish()
        try await repository.save(recording)
        return recording
    }

    /// The store following the stored Recording on its finish screen.
    private func storeOnTheFinishScreen(defaultVisibility: ActivityVisibility = .public) async -> (RecordingStore, Task<Void, Never>) {
        let store = makeStore(defaultVisibility: defaultVisibility)
        let observation = Task { await store.observe() }
        await until(store) { $0.screen == .finishing }
        return (store, observation)
    }

    @Test func saveTurnsTheRecordingIntoALocalActivityWithItsProvisionalValues() async throws {
        let recording = try await finishedRide()
        let (store, observation) = await storeOnTheFinishScreen()
        defer { observation.cancel() }

        let saved = await store.save(title: "Col de la Croix", visibility: .followers)

        #expect(saved)
        let activity = try #require(try await activities.activity(recording.id))
        #expect(activity.state == .recorded)
        #expect(activity.sport == .ride)
        #expect(activity.title == "Col de la Croix")
        #expect(activity.visibility == .followers)
        #expect(activity.startedAt == start)
        // The end is the start of the final Pause, which is not sent.
        #expect(activity.endedAt == start.addingTimeInterval(720))
        #expect(activity.elapsedTimeS == 720)
        #expect(activity.movingTimeS == 600)
        // The leg across the Pause does not count.
        #expect(abs(activity.distance.meters - 1_000) < 1)
        #expect(try await activities.operation(for: recording.id)?.step == .create)
    }

    @Test func saveDeletesTheRecordingButKeepsItsPointsAndPauses() async throws {
        let recording = try await finishedRide()
        let (store, observation) = await storeOnTheFinishScreen()
        defer { observation.cancel() }

        _ = await store.save(title: "", visibility: .public)

        #expect(try await repository.load() == nil)
        let trace = try await activities.trace(of: recording.id)
        #expect(trace.points.count == 3)
        #expect(trace.pauses.count == 1)
    }

    @Test func afterSaveTheRecordTabIsBackOnThePreStartScreenWithTheGPSReleased() async throws {
        _ = try await finishedRide()
        let (store, observation) = await storeOnTheFinishScreen()
        defer { observation.cancel() }

        _ = await store.save(title: "", visibility: .public)
        await until(store) { $0.snapshot == nil }

        #expect(store.screen == .preStart)
        #expect(provider.endBackgroundTrackingCount == 1)
        #expect(!provider.isRecordingStreamActive)
        // The saved sport is preselected next time.
        #expect(store.sport == .ride)
        #expect(preferences.lastSavedSport == .ride)
    }

    @Test func anEmptyTitleIsSavedAsTheDefaultOne() async throws {
        let recording = try await finishedRide()
        let (store, observation) = await storeOnTheFinishScreen()
        defer { observation.cancel() }

        _ = await store.save(title: "  ", visibility: .public)

        // 07:00 UTC is 09:00 in Paris.
        #expect(try await activities.activity(recording.id)?.title == "Sortie à vélo le matin")
    }

    @Test func theVisibilityIsPreselectedFromTheCachedDefault() async throws {
        _ = try await finishedRide()
        let (store, observation) = await storeOnTheFinishScreen(defaultVisibility: .private)
        defer { observation.cancel() }

        #expect(store.defaultVisibility == .private)
    }

    @Test func aRecordingTooShortCannotBeSaved() async throws {
        var recording = Recording(sport: .run, startedAt: start)
        try await repository.create(recording)
        try await repository.append(sample(0, north: 0), to: recording.id)
        try await repository.append(sample(30, north: 100), to: recording.id)
        recording.pause(at: start.addingTimeInterval(30))
        recording.finish()
        try await repository.save(recording)
        let (store, observation) = await storeOnTheFinishScreen()
        defer { observation.cancel() }

        #expect(await store.save(title: "", visibility: .public) == false)

        #expect(store.screen == .finishing)
        #expect(try await activities.activity(recording.id) == nil)
        #expect(try await repository.load() != nil)
    }
}
