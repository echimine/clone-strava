import Foundation
import Testing
@testable import StravaClone

/// The local card's carousel (ADR-037 §6): the static map of the local points, then the Media
/// picked on the finish screen with their status; once processed, the server's card takes them
/// over without a duplicate.
@MainActor
struct LocalActivityCardMediaTests {
    private let board = MediaUploadBoard()

    private func sending(_ media: ActivityMedia) -> ActivityMedia {
        var media = media
        media.upload = .sending(progress: 0.4)
        return media
    }

    private func ids(_ slides: [ActivitySlide<ActivityMedia>]) -> [String] {
        slides.map { slide in
            switch slide {
            case .map: "map"
            case .media(let media): media.id.uuidString
            }
        }
    }

    @Test func theLocalCardShowsTheMapThenItsLocalMedia() {
        let card = LocalActivityCard.fixture()
        let first = sending(.fixture())
        let second = sending(.fixture())
        board.show([card.id: [.init(position: 1, media: second), .init(position: 0, media: first)]])

        let slides = card.slides(merging: board)

        #expect(ids(slides) == ["map", first.id.uuidString, second.id.uuidString])
        if case .media(let shown) = slides[1] { #expect(shown.upload == .sending(progress: 0.4)) }
    }

    @Test func mediaFirstPutsTheFirstMediaBeforeTheMap() {
        var card = LocalActivityCard.fixture()
        card = LocalActivityCard(
            activity: { var activity = card.activity; activity.mediaFirst = true; return activity }(),
            status: card.status,
            route: card.route
        )
        let photo = sending(.fixture())
        board.show([card.id: [.init(position: 0, media: photo)]])

        #expect(ids(card.slides(merging: board)) == [photo.id.uuidString, "map"])
    }

    @Test func withoutMediaTheLocalCardIsTheMapAlone() {
        #expect(ids(LocalActivityCard.fixture().slides(merging: board)) == ["map"])
    }

    @Test func afterProcessingTheServerCardTakesTheMediaOverWithoutADuplicate() {
        let id = ActivityID()
        let confirmed = ActivityMedia.fixture()
        let stillSending = sending(.fixture())
        board.show([id: [.init(position: 1, media: stillSending)]])
        board.confirm(confirmed, position: 0, of: id)
        let post = ActivityPost(
            id: id, title: "Sortie", sport: .run, startedAt: .now, locationName: nil, distance: nil,
            movingTime: nil, elevationGain: nil, avgSpeedMs: nil,
            route: EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC"), routeTrimmed: false,
            author: ActivityAuthor(id: "1", displayName: "Camille", avatarURL: nil),
            engagement: ActivityEngagement(kudosCount: 0, commentCount: 0, viewerHasKudoed: false),
            recentKudos: [], viewerIsAuthor: true, media: [confirmed]
        )

        #expect(ids(post.slides(merging: board)) == ["map", confirmed.id.uuidString, stillSending.id.uuidString])
    }
}
