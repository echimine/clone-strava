import Foundation
import Testing
@testable import StravaClone

@MainActor
struct RecordingStoreTests {
    private let provider = FakeLocationProvider()
    private let repository: GRDBRecordingRepository
    private let service: RecordingService
    private let activities: GRDBLocalActivityStore

    init() throws {
        let database = try AppDatabase.inMemory()
        repository = GRDBRecordingRepository(database: database)
        activities = GRDBLocalActivityStore(database: database)
        service = RecordingService(locationProvider: provider, repository: repository)
    }

    private func makeStore(
        lastSavedSport: RecordingSport? = nil,
        fullAccuracy: Bool = true
    ) -> RecordingStore {
        RecordingStore(
            service: service,
            preferences: InMemoryRecordingPreferences(lastSavedSport: lastSavedSport),
            ensureFullAccuracy: { fullAccuracy },
            saveRecording: SaveRecording(service: service, activities: activities),
            defaultVisibility: { .public }
        )
    }

    /// Waits for the store to follow the service's stream.
    private func until(_ store: RecordingStore, _ condition: (RecordingStore) -> Bool) async {
        while !condition(store) {
            await Task.yield()
        }
    }

    @Test func preselectsRunTheFirstTime() {
        #expect(makeStore().sport == .run)
    }

    @Test func preselectsTheSportOfTheLastSavedRecording() {
        #expect(makeStore(lastSavedSport: .hike).sport == .hike)
    }

    @Test func startsWithTheChosenSport() async throws {
        let store = makeStore()
        let observation = Task { await store.observe() }
        defer { observation.cancel() }
        await until(store) { $0.screen == .preStart }

        store.sport = .ride
        await store.start()
        await until(store) { $0.snapshot != nil }

        #expect(store.screen == .recording)
        #expect(try await repository.load()?.recording.sport == .ride)
    }

    @Test func doesNotStartWithoutFullAccuracy() async throws {
        let store = makeStore(fullAccuracy: false)

        await store.start()

        #expect(store.errorMessage == RecordingMessages.fullAccuracyRefused)
        #expect(try await repository.load() == nil)
        #expect(provider.beginBackgroundTrackingCount == 0)
    }

    @Test func showsTheRecordingAlreadyInProgress() async throws {
        var recording = Recording(sport: .walk, startedAt: Date())
        recording.pause(at: Date())
        recording.finish()
        try await repository.create(recording)
        let store = makeStore()

        let observation = Task { await store.observe() }
        defer { observation.cancel() }
        await until(store) { $0.snapshot != nil }

        #expect(store.screen == .finishing)
    }

    @Test func deleteReturnsToThePreStartScreen() async throws {
        let store = makeStore()
        let observation = Task { await store.observe() }
        defer { observation.cancel() }
        await store.start()
        await until(store) { $0.snapshot != nil }

        await store.pause()
        await store.finish()
        await until(store) { $0.screen == .finishing }
        await store.delete()
        await until(store) { $0.snapshot == nil }

        #expect(store.screen == .preStart)
        #expect(try await repository.load() == nil)
    }
}

final class InMemoryRecordingPreferences: RecordingPreferences, @unchecked Sendable {
    var lastSavedSport: RecordingSport?

    init(lastSavedSport: RecordingSport? = nil) {
        self.lastSavedSport = lastSavedSport
    }

    func rememberSavedSport(_ sport: RecordingSport) {
        lastSavedSport = sport
    }
}
