import AVFoundation
import Foundation
import Testing
@testable import StravaClone

/// The viewer's videos (ADR-037 §10): the one on screen plays with sound, changing Media pauses
/// it, and the viewer takes the app's single video playback from the carousel under it.
@MainActor
struct MediaViewerModelTests {
    private final class SpyPlayer: AVPlayer {
        private(set) var isPlaying = false
        override func play() { isPlaying = true }
        override func pause() { isPlaying = false }
    }

    private final class Players {
        private(set) var made: [URL: SpyPlayer] = [:]
        func make(_ url: URL) -> AVPlayer {
            let player = SpyPlayer()
            made[url] = player
            return player
        }
    }

    private let photo = ActivityMedia.fixture()
    private let firstVideo = ActivityMedia.fixture(kind: .video)
    private let secondVideo = ActivityMedia.fixture(kind: .video)

    private func makeModel(startingOn media: ActivityMedia, players: Players, playback: VideoPlayback = VideoPlayback()) throws -> MediaViewerModel {
        var post = ActivityPost.fixture()
        post.media = [photo, firstVideo, secondVideo]
        let request = try #require(MediaViewerRequest.activity(post, at: media))
        return MediaViewerModel(request: request, playback: playback, makePlayer: players.make)
    }

    @Test func aVideoPlaysWithSoundAsSoonAsItIsOnScreen() throws {
        let players = Players()
        let model = try makeModel(startingOn: firstVideo, players: players)

        model.appear()

        let player = try #require(players.made[firstVideo.url])
        #expect(player.isPlaying)
        #expect(!player.isMuted)
        #expect(model.player(for: firstVideo) === player)
    }

    @Test func changingMediaPausesThePreviousVideo() throws {
        let players = Players()
        let model = try makeModel(startingOn: firstVideo, players: players)
        model.appear()

        model.show(2)

        #expect(players.made[firstVideo.url]?.isPlaying == false)
        #expect(players.made[secondVideo.url]?.isPlaying == true)
        #expect(model.position == "3 sur 3")

        model.show(0)

        #expect(players.made[secondVideo.url]?.isPlaying == false)
        #expect(model.current.media == photo)
    }

    @Test func aPhotoMakesNoPlayer() throws {
        let players = Players()
        let model = try makeModel(startingOn: photo, players: players)

        model.appear()

        #expect(players.made.isEmpty)
        #expect(model.position == "1 sur 3")
    }

    @Test func theViewerPausesTheCarouselUntilItCloses() throws {
        let playback = VideoPlayback()
        let carouselVideo = UUID()
        playback.claim(carouselVideo)
        let players = Players()
        let model = try makeModel(startingOn: firstVideo, players: players, playback: playback)

        model.appear()
        #expect(playback.playing != carouselVideo)

        model.disappear()
        #expect(playback.playing == carouselVideo)
        #expect(players.made[firstVideo.url]?.isPlaying == false)
    }
}
