import Foundation
import Testing
@testable import StravaClone

/// "Photos et vidéos" on the finish screen (ADR-037 §6): each Media picked is exported at once,
/// Save writes its `media_upload` row in the transaction of the local Activity and
/// `create_activity`, and nothing is sent while the server does not have the Activity. Real GRDB
/// in memory for the Recording, the local Activities and the rows; real exports into real files.
@MainActor
struct RecordingMediaTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)
    private let provider = FakeLocationProvider()
    private let repository: GRDBRecordingRepository
    private let activities: GRDBLocalActivityStore
    private let service: RecordingService
    private let media: MediaUploadHarness
    private let server = FakeMediaUploadServer()
    private let transfer = FakeMediaTransfer()
    private let queue: MediaUploadQueue

    init() throws {
        let database = try AppDatabase.inMemory()
        repository = GRDBRecordingRepository(database: database)
        activities = GRDBLocalActivityStore(database: database)
        service = RecordingService(locationProvider: provider, repository: repository)
        media = try MediaUploadHarness(database: database)
        let activities = activities
        queue = media.makeQueue(transfer: transfer, server: server, canSend: { await activities.isKnownToServer($0) })
    }

    private func makeStore() -> RecordingStore {
        RecordingStore(
            service: service,
            preferences: InMemoryRecordingPreferences(),
            itineraries: FakeItineraryCacheReader(),
            ensureFullAccuracy: { true },
            saveRecording: SaveRecording(service: service, activities: GRDBRecordingSaver(activities: activities)),
            mediaUploads: ActivityMediaUploads(queue: queue, analytics: media.analytics),
            defaultVisibility: { .public }
        )
    }

    private func sample(_ seconds: TimeInterval, north: Double) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: 45.764, longitude: 4.8357).offset(northMeters: north),
            altitude: nil,
            horizontalAccuracy: 5,
            timestamp: start.addingTimeInterval(seconds)
        )
    }

    /// A 12-min ride, finished, its store on the finish screen.
    private func onTheFinishScreen() async throws -> (RecordingStore, Recording, Task<Void, Never>) {
        var recording = Recording(sport: .ride, startedAt: start)
        try await repository.create(recording)
        try await repository.append(sample(0, north: 0), to: recording.id)
        try await repository.append(sample(720, north: 3_000), to: recording.id)
        recording.pause(at: start.addingTimeInterval(720))
        recording.finish()
        try await repository.save(recording)
        let store = makeStore()
        let observation = Task { await store.observe() }
        while store.screen != .finishing {
            await Task.yield()
        }
        return (store, recording, observation)
    }

    private func isExported(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: media.files.url(of: MediaUploadFile.originalPhoto, mediaID: id).path)
    }

    /// A photo whose library read waits for `gate` (an export still running at Save).
    private func slowPhoto() -> (PickedMedia, AsyncStream<Void>.Continuation) {
        let (gate, open) = AsyncStream.makeStream(of: Void.self)
        let data = MediaUploadHarness.cameraPhoto(width: 1_200, height: 900)
        let photo = PickedMedia(source: MediaSource(kind: .photo) {
            for await _ in gate { break }
            return .image(data)
        })
        return (photo, open)
    }

    // MARK: - Export from the selection

    @Test func aPickedPhotoIsExportedBeforeSave() async throws {
        let (store, _, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let photo = MediaUploadHarness.photo()

        store.mediaDraft.add([photo])

        #expect(await eventually { queue.board.preparation(of: photo.id) == .ready })
        #expect(isExported(photo.id))
        #expect(try await media.store.count() == 0)
    }

    @Test func anOriginalTheLibraryCannotHandShowsUnavailable() async throws {
        let (store, _, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let offline = PickedMedia(source: MediaSource(kind: .photo) { throw URLError(.notConnectedToInternet) })

        store.mediaDraft.add([offline])

        #expect(await eventually { queue.board.preparation(of: offline.id) == .unavailable })
    }

    // MARK: - Save

    @Test func offlineSaveWritesTheActivityItsCreationAndTheMediaRowsTogether() async throws {
        let (store, recording, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let first = MediaUploadHarness.photo()
        let second = MediaUploadHarness.photo()
        store.mediaDraft.add([first, second])
        store.mediaDraft.putFirst(second.id)
        #expect(await eventually { queue.board.preparation(of: first.id) == .ready && queue.board.preparation(of: second.id) == .ready })

        #expect(await store.save(title: "Col", visibility: .public))

        let activity = try #require(try await activities.activity(recording.id))
        #expect(activity.state == .recorded)
        #expect(activity.mediaFirst)
        #expect(try await activities.operation(for: recording.id)?.step == .create)
        let rows = try await media.store.all().sorted { $0.position < $1.position }
        #expect(rows.map(\.mediaID) == [second.id, first.id])
        #expect(rows.map(\.position) == [0, 1])
        #expect(rows.allSatisfy { $0.activityID == recording.id && $0.state == .uploading && $0.width == 1_200 })
        // The server does not have the Activity yet: nothing goes.
        await queue.send(ignoringBackoff: true)
        #expect(server.calls.isEmpty)
        #expect(transfer.started.isEmpty)
    }

    @Test func aFailingMediaRowLeavesNeitherTheActivityNorItsCreation() async throws {
        let (store, recording, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let photo = MediaUploadHarness.photo()
        // A row with the same id already exists: the insert fails inside the transaction.
        try await media.store.insert([MediaUpload(
            mediaID: photo.id, activityID: ActivityID(), kind: .photo, position: 0, state: .failed, failure: .network,
            files: [], attempts: 0, nextAttemptAt: start, createdAt: start
        )])
        store.mediaDraft.add([photo])

        #expect(await store.save(title: "", visibility: .public) == false)

        #expect(try await activities.activity(recording.id) == nil)
        #expect(try await activities.operation(for: recording.id) == nil)
        #expect(try await repository.load() != nil)
        #expect(store.screen == .finishing)
    }

    @Test func anExportStillRunningAtSaveIsSavedExportingThenFinishesOnItsRow() async throws {
        let (store, recording, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let (photo, open) = slowPhoto()
        store.mediaDraft.add([photo])

        #expect(await store.save(title: "", visibility: .public))
        #expect(try await media.store.upload(photo.id)?.state == .exporting)

        open.yield()
        #expect(await eventually { (try? await media.store.upload(photo.id))?.state == .uploading })
        #expect(try await media.store.upload(photo.id)?.activityID == recording.id)
        #expect(server.calls.isEmpty)
    }

    @Test func saveSendsActivityMediaSavedFromTheRecording() async throws {
        let (store, _, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let photo = MediaUploadHarness.photo()
        store.mediaDraft.add([photo])
        store.mediaDraft.putFirst(photo.id)

        _ = await store.save(title: "", visibility: .public)

        let expected = AnalyticsEvent.activityMediaSaved(entry: .recording, ActivityMediaSaved(
            photosAdded: 1, videosAdded: 0, videosTrimmed: 0, mediaRemoved: 0, mediaFirst: true, mediaCount: 1
        ))
        #expect(await eventually { media.analytics.events == [expected] })
    }

    @Test func saveWithoutMediaSendsNoMediaEvent() async throws {
        let (store, recording, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }

        _ = await store.save(title: "", visibility: .public)

        #expect(try await activities.activity(recording.id)?.mediaFirst == false)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(media.analytics.events.isEmpty)
    }

    // MARK: - Resume and Delete

    @Test func resumeKeepsTheSelection() async throws {
        let (store, _, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let photo = MediaUploadHarness.photo()
        store.mediaDraft.add([photo])

        await store.reopen()
        await store.finish()

        #expect(store.mediaDraft.added.map(\.id) == [photo.id])
        #expect(await eventually { queue.board.preparation(of: photo.id) == .ready })
    }

    @Test func deleteDropsThePickedMediaAndTheirFiles() async throws {
        let (store, _, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let photo = MediaUploadHarness.photo()
        store.mediaDraft.add([photo])
        #expect(await eventually { isExported(photo.id) })

        await store.delete()

        #expect(store.mediaDraft.count == 0)
        #expect(queue.board.preparation(of: photo.id) == nil)
        #expect(!isExported(photo.id))
        #expect(try await media.store.count() == 0)
    }

    @Test func removingAPickedMediaFromTheStripDeletesItsExport() async throws {
        let (store, _, observation) = try await onTheFinishScreen()
        defer { observation.cancel() }
        let photo = MediaUploadHarness.photo()
        store.mediaDraft.add([photo])
        #expect(await eventually { isExported(photo.id) })

        store.mediaDraft.remove(photo.id)

        #expect(!isExported(photo.id))
        #expect(queue.board.preparation(of: photo.id) == nil)
    }
}
