import Foundation
import Testing
@testable import StravaClone

/// The Record tab after the app was killed, and a sign-out during a Recording (ADR-031 §10).
@MainActor
struct RecordingStoreResumeTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let provider = FakeLocationProvider()
    private let repository: GRDBRecordingRepository
    private let service: RecordingService

    init() throws {
        repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        service = RecordingService(locationProvider: provider, repository: repository, now: { [start] in start.addingTimeInterval(900) })
    }

    private func makeStore(launch: RecordingLaunch) -> RecordingStore {
        RecordingStore(
            service: service,
            preferences: InMemoryRecordingPreferences(),
            launch: launch,
            ensureFullAccuracy: { true }
        )
    }

    private func storeActiveRecording() async throws {
        let recording = Recording(sport: .ride, startedAt: start)
        try await repository.create(recording)
        let point = LocationSample(
            coordinate: Coordinate(latitude: 45.764, longitude: 4.8357),
            altitude: nil,
            horizontalAccuracy: 5,
            timestamp: start.addingTimeInterval(5)
        )
        _ = try await repository.append(point, to: recording.id)
    }

    private func until(_ store: RecordingStore, _ condition: (RecordingStore) -> Bool) async {
        while !condition(store) {
            await Task.yield()
        }
    }

    @Test func theAthleteFindsAnInterruptedRecordingPaused() async throws {
        try await storeActiveRecording()
        let store = makeStore(launch: .openedByAthlete)

        let observation = Task { await store.observe() }
        defer { observation.cancel() }
        await until(store) { $0.snapshot != nil }

        #expect(store.screen == .recording)
        #expect(store.snapshot?.recording.phase == .paused)
        #expect(store.snapshot?.recording.currentPauseStartedAt == start.addingTimeInterval(5))
    }

    @Test func afterABackgroundRelaunchTheRecordingIsStillMoving() async throws {
        try await storeActiveRecording()
        let store = makeStore(launch: .relaunchedInBackground)

        let observation = Task { await store.observe() }
        defer { observation.cancel() }
        await until(store) { $0.snapshot != nil }

        #expect(store.snapshot?.recording.phase == .active)
    }

    @Test func signingOutWithoutARecordingAsksNothing() async {
        #expect(await makeStore(launch: .openedByAthlete).signOutWarning() == nil)
    }

    @Test func signingOutDuringARecordingWarnsItWillBeDeletedThenDeletesIt() async throws {
        try await storeActiveRecording()
        let store = makeStore(launch: .openedByAthlete) // the Record tab was never opened

        #expect(await store.signOutWarning() == RecordingMessages.signOutWarning)
        await store.delete()

        #expect(try await repository.load() == nil)
        #expect(provider.endBackgroundTrackingCount == 1)
        #expect(await store.signOutWarning() == nil)
    }
}
