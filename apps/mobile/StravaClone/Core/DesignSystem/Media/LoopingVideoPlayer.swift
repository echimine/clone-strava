import AVFoundation
import SwiftUI

/// A video played in a loop, filling its frame, without controls (ADR-037 §10): the carousel's
/// current video. `AVPlayer` reads the pre-signed URL directly, with Range requests (ADR-037 §1).
/// The player exists only while the view is shown: removing the view stops it.
struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL
    var muted = true

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = muted
        player.preventsDisplaySleepDuringVideoPlayback = false
        MediaAudioSession.prepare(muted: muted)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard let player = view.playerLayer.player, player.isMuted != muted else { return }
        MediaAudioSession.prepare(muted: muted)
        player.isMuted = muted
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
        coordinator.looper?.disableLooping()
        view.playerLayer.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        // swiftlint:disable:next force_cast
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// The audio session for Media videos: a muted video mixes with the music the athlete is
/// listening to (`.ambient`); turning the sound on takes over the audio (`.playback`).
enum MediaAudioSession {
    static func prepare(muted: Bool) {
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category = muted ? .ambient : .playback
        guard session.category != category else { return }
        try? session.setCategory(category, mode: .moviePlayback)
        if !muted {
            try? session.setActive(true)
        }
    }
}
