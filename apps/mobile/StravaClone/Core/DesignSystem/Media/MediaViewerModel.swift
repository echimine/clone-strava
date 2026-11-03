import AVFoundation
import Observation

/// The viewer's state (ADR-037 §10): the Media on screen, "3 sur 8", and its videos. The video
/// on screen plays with sound; another Media coming pauses it. While shown, the viewer holds
/// the app's single video playback (`VideoPlayback`), so the carousel under the full-screen
/// cover, which never disappears, stops its muted loop; closing gives it back.
@MainActor
@Observable
final class MediaViewerModel {
    let request: MediaViewerRequest
    private(set) var index: Int
    /// The videos already shown, kept so that coming back resumes where it was paused.
    private(set) var players: [UUID: AVPlayer] = [:]

    @ObservationIgnored private let playback: VideoPlayback
    @ObservationIgnored private let makePlayer: (URL) -> AVPlayer
    @ObservationIgnored private let playbackID = UUID()

    init(
        request: MediaViewerRequest,
        playback: VideoPlayback,
        makePlayer: @escaping (URL) -> AVPlayer = { AVPlayer(url: $0) }
    ) {
        self.request = request
        self.playback = playback
        self.makePlayer = makePlayer
        index = request.start
    }

    var current: MediaViewerItem { request.items[index] }

    /// "3 sur 8"; nil from the Gallery.
    var position: String? { request.position(at: index) }

    func player(for media: ActivityMedia) -> AVPlayer? {
        players[media.id]
    }

    /// The viewer is on screen: takes the playback from the carousel, plays the current video.
    func appear() {
        playback.claim(playbackID)
        playCurrent()
    }

    /// A swipe to the Media at `index`.
    func show(_ index: Int) {
        guard request.items.indices.contains(index), index != self.index else { return }
        self.index = index
        playCurrent()
    }

    /// Closed: every video stops and the carousel's loop may play again.
    func disappear() {
        players.values.forEach { $0.pause() }
        playback.release(playbackID)
    }

    private func playCurrent() {
        let media = current.media
        for (id, player) in players where id != media.id {
            player.pause()
        }
        guard media.kind == .video else { return }
        let player = players[media.id] ?? makePlayer(media.url)
        players[media.id] = player
        player.isMuted = false
        MediaAudioSession.prepare(muted: false)
        player.play()
    }
}
