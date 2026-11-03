import Foundation
import Testing
@testable import StravaClone

/// What the viewer opens on (ADR-037 §10): the Activity's Media without the map, on the Media
/// touched, with "3 sur 8"; from the Gallery, any list of Media and no "n sur N".
struct MediaViewerRequestTests {
    private func post(mediaCount: Int) -> ActivityPost {
        var post = ActivityPost.fixture(title: "Sortie du soir")
        post.media = (0..<mediaCount).map { _ in .fixture() }
        return post
    }

    @Test func opensOnTheTouchedMediaWithItsPosition() throws {
        let post = post(mediaCount: 8)

        let request = try #require(MediaViewerRequest.activity(post, at: post.media[2]))

        #expect(request.items.map(\.media) == post.media)
        #expect(request.start == 2)
        #expect(request.position(at: request.start) == "3 sur 8")
    }

    @Test func eachMediaKnowsItsActivity() throws {
        let post = post(mediaCount: 2)

        let request = try #require(MediaViewerRequest.activity(post, at: post.media[0]))

        #expect(request.items.map(\.activity) == [
            MediaViewerActivity(id: post.id, title: "Sortie du soir", startedAt: post.startedAt),
            MediaViewerActivity(id: post.id, title: "Sortie du soir", startedAt: post.startedAt),
        ])
    }

    @Test func aMediaThePostNoLongerHasOpensNothing() {
        let post = post(mediaCount: 2)

        #expect(MediaViewerRequest.activity(post, at: .fixture()) == nil)
    }

    @Test func theGalleryHasNoPosition() throws {
        let items = post(mediaCount: 3).media.map {
            MediaViewerItem(media: $0, activity: MediaViewerActivity(id: ActivityID(), title: "Trail", startedAt: .now))
        }

        let request = try #require(MediaViewerRequest.gallery(items, at: items[1].media))

        #expect(request.start == 1)
        #expect(request.mode == .gallery)
        #expect(request.position(at: 1) == nil)
    }
}
