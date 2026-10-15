import Foundation
import Testing
@testable import StravaClone

/// The auto-pause switch of the pre-start screen and of the "…" menu (ADR-031 §4).
@MainActor
struct RecordingAutoPauseStoreTests {
    private let provider = FakeLocationProvider()
    private let motion = FakeMotionActivityProvider()
    private let preferences = InMemoryAutoPausePreferences()
    private let repository: GRDBRecordingRepository
    private let service: RecordingService

    init() throws {
        repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        service = RecordingService(locationProvider: provider, repository: repository, motionProvider: motion)
    }

    private func makeStore(sport: RecordingSport = .ride) -> RecordingStore {
        let motion = motion
        let store = RecordingStore(
            service: service,
            preferences: InMemoryRecordingPreferences(lastSavedSport: sport),
            ensureFullAccuracy: { true },
            autoPausePreferences: preferences,
            requestMotionAuthorization: { await motion.requestAuthorization() }
        )
        return store
    }

    private func until(_ store: RecordingStore, _ condition: (RecordingStore) -> Bool) async {
        while !condition(store) {
            await Task.yield()
        }
    }

    @Test func onForARideOffForARunAbsentOnFoot() {
        let store = makeStore(sport: .ride)
        #expect(store.offersAutoPause)
        #expect(store.autoPause)

        store.sport = .run
        #expect(store.offersAutoPause)
        #expect(!store.autoPause)

        store.sport = .walk
        #expect(!store.offersAutoPause)
    }

    @Test func theSwitchIsRememberedPerSport() async {
        let store = makeStore(sport: .ride)
        await store.setAutoPause(false)

        store.sport = .run
        #expect(!store.autoPause)
        store.sport = .ride
        #expect(!store.autoPause)
        #expect(!makeStore(sport: .ride).autoPause)
    }

    @Test func turningItOnForARunAsksForMotionAccess() async {
        let store = makeStore(sport: .run)

        await store.setAutoPause(true)

        #expect(motion.authorizationRequests == 1)
        #expect(store.autoPause)
        #expect(preferences.autoPause(for: .run) == true)
    }

    @Test func refusedMotionAccessPutsTheSwitchBackOff() async {
        motion.isAuthorized = false
        let store = makeStore(sport: .run)

        await store.setAutoPause(true)

        #expect(!store.autoPause)
        #expect(preferences.autoPause(for: .run) == nil)
    }

    @Test func theRecordingStartsWithTheSwitch() async throws {
        let store = makeStore(sport: .ride)
        let observation = Task { await store.observe() }
        defer { observation.cancel() }
        await until(store) { $0.screen == .preStart }

        await store.start()
        await until(store) { $0.snapshot != nil }

        #expect(try await repository.load()?.recording.autoPauseEnabled == true)
    }

    @Test func theMenuChangesTheSwitchDuringTheRecording() async throws {
        let store = makeStore(sport: .ride)
        let observation = Task { await store.observe() }
        defer { observation.cancel() }
        await until(store) { $0.screen == .preStart }
        await store.start()
        await until(store) { $0.snapshot != nil }

        await store.setAutoPause(false)

        #expect(store.snapshot?.recording.autoPauseEnabled == false)
        #expect(try await repository.load()?.recording.autoPauseEnabled == false)
    }
}

final class InMemoryAutoPausePreferences: AutoPausePreferences, @unchecked Sendable {
    private var values: [RecordingSport: Bool] = [:]

    func autoPause(for sport: RecordingSport) -> Bool? {
        values[sport]
    }

    func rememberAutoPause(_ enabled: Bool, for sport: RecordingSport) {
        values[sport] = enabled
    }
}
