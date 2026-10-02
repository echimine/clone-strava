import Testing
@testable import StravaClone

@MainActor
struct RecordingServiceTests {
    @Test func startTracksInBackgroundAndRecordsSamples() async throws {
        let provider = FakeLocationProvider()
        let repository = FakeRecordingRepository()
        let service = RecordingService(locationProvider: provider, repository: repository)

        var updates = try await service.start().makeAsyncIterator()
        _ = await updates.next() // initial state

        #expect(provider.beginBackgroundTrackingCount == 1)
        #expect(provider.isUpdating)

        // The service's update stream keeps only the newest state: wait for each one.
        provider.send(.fixture(latitude: 48.8566, longitude: 2.3522))
        _ = await updates.next()
        provider.send(.fixture(latitude: 48.8576, longitude: 2.3522))
        let recording = try #require(await updates.next())

        #expect(recording.distance.meters > 100)
        #expect(await repository.appended.count == 2)
        #expect(await repository.created.count == 1)
    }

    @Test func stopEndsTrackingAndReleasesTheGPS() async throws {
        let provider = FakeLocationProvider()
        let repository = FakeRecordingRepository()
        let service = RecordingService(locationProvider: provider, repository: repository)
        _ = try await service.start()

        try await service.stop()
        while provider.sampleSubscriberCount > 0 {
            await Task.yield()
        }

        #expect(provider.endBackgroundTrackingCount == 1)
        #expect(!provider.isUpdating)
        #expect(await repository.finished.count == 1)
    }

    @Test func sharesTheSourceWithOtherSubscribers() async throws {
        let provider = FakeLocationProvider()
        let service = RecordingService(locationProvider: provider, repository: FakeRecordingRepository())
        let mapStream = await provider.samples() // e.g. the map puck

        _ = try await service.start()
        try await service.stop()
        while provider.sampleSubscriberCount > 1 {
            await Task.yield()
        }

        #expect(provider.isUpdating) // the map still listens
        _ = mapStream
    }
}
