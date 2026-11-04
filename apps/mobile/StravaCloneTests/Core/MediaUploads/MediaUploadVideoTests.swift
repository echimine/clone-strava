import Foundation
import Testing
@testable import StravaClone

/// A video's journey through the same queue as the photos (ADR-037 §3, §5): its three files,
/// then a confirmation that carries its duration; and the "Vidéo coupée à 1 min" count.
@MainActor
@Suite(.serialized)
struct MediaUploadVideoTests {
    private nonisolated static let videoFiles = ["original.mp4", "poster.jpg", "thumb.jpg"]

    init() {
        MediaUploadHarness.resetNetwork()
    }

    @Test func thePickedVideosThreeFilesAreSentThenItsConfirmationCarriesItsDuration() async throws {
        let harness = try MediaUploadHarness()
        let videoID = Locked<UUID?>(nil)
        MediaUploadHarness.route { step in
            step == "upload-urls"
                ? MediaUploadHarness.uploadURLs(names: Self.videoFiles)
                : MediaUploadHarness.confirmedVideo(videoID.value!, durationMs: 3_000)
        }
        let transfer = FakeMediaTransfer()
        let queue = harness.makeQueue(transfer: transfer)
        let video = MediaUploadHarness.video(try await TestMovie.make(seconds: 3))
        videoID.value = video.id

        await queue.enqueue([QueuedMedia(media: video, position: 1)], to: harness.activityID)
        #expect(await eventually { transfer.started.count == 3 })

        let urls = try #require(try harness.lastBody("upload-urls"))
        #expect(urls["kind"] as? String == "video")
        let files = try #require(urls["files"] as? [[String: Any]])
        #expect(files.map { $0["name"] as? String } == Self.videoFiles)
        #expect(files.map { $0["contentType"] as? String } == ["video/mp4", "image/jpeg", "image/jpeg"])
        #expect(Set(transfer.startedNames) == Set(Self.videoFiles))
        let local = try #require(queue.board.media(of: harness.activityID, merging: []).first)
        #expect(local.posterURL?.lastPathComponent == "poster.jpg")
        #expect(local.kind == .video)
        #expect(local.duration != nil, "the local tile shows its duration")

        for put in transfer.started {
            await queue.handle(.finished(put.key, status: 200))
        }

        let confirmation = try #require(try harness.lastBody("media"))
        #expect(confirmation["kind"] as? String == "video")
        #expect(confirmation["position"] as? Int == 1)
        let durationMs = try #require(confirmation["durationMs"] as? Int)
        #expect((2_500 ... 3_500).contains(durationMs))
        #expect(try await harness.store.upload(video.id) == nil)
        #expect(queue.board.media(of: harness.activityID, merging: []).first?.kind == .video)
    }

    @Test func aVideoThatCannotBeExportedTurnsTheTileFailed() async throws {
        let harness = try MediaUploadHarness()
        let queue = harness.makeQueue(transfer: FakeMediaTransfer())
        let notAMovie = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-movie-\(UUID()).mov")
        try Data("not a movie".utf8).write(to: notAMovie)
        let video = MediaUploadHarness.video(notAMovie)

        await queue.enqueue([QueuedMedia(media: video, position: 0)], to: harness.activityID)

        #expect(await eventually { (try? await harness.store.upload(video.id))?.state == .failed })
        #expect(try await harness.store.upload(video.id)?.failure == .exportFailed)
        #expect(harness.requestLines.isEmpty)
        #expect(harness.analytics.events == [.mediaUploadFailed(kind: .video, reason: .exportFailed)])
    }

    @Test func theDraftCountsThePickedVideosLongerThanAMinute() async throws {
        var draft = MediaDraft(media: [], hasMap: true, mediaFirst: false)
        let long = MediaUploadHarness.video(try await TestMovie.make(seconds: 65, audio: false))
        let short = MediaUploadHarness.video(try await TestMovie.make(seconds: 4, audio: false))

        draft.add([long, MediaUploadHarness.photo(), short])

        #expect(await long.isTrimmed())
        #expect(await !short.isTrimmed())
        #expect(await draft.videosTrimmed() == 1)
    }

    @Test func aPickedVideosCopyIsDeletedWithIt() async throws {
        let copy = try await TestMovie.make(seconds: 1, audio: false)
        var movie: PickedMovie? = PickedMovie { copy }
        #expect(try await movie?.file() == copy)

        movie = nil

        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }
}
