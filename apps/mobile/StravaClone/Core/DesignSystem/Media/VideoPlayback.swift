import SwiftUI

/// Which video plays (ADR-037 §10): one at a time in the whole app. A video slide claims the
/// playback when it becomes the current slide of a shown carousel and releases it when it stops
/// being current or leaves the screen. The last claim plays; when it is released, the previous
/// claim still shown plays again (scrolling back up the feed, coming back from the detail).
/// One instance for the app, made by `Di` and set in the environment by the app shell.
@MainActor
@Observable
final class VideoPlayback {
    private var claims: [UUID] = []

    nonisolated init() {}

    /// The one video allowed to play, if any.
    var playing: UUID? { claims.last }

    func claim(_ id: UUID) {
        claims.removeAll { $0 == id }
        claims.append(id)
    }

    func release(_ id: UUID) {
        claims.removeAll { $0 == id }
    }
}

extension EnvironmentValues {
    /// Shared by every carousel, so only one video plays at a time. Set by the app shell; a fresh
    /// one in the previews.
    @Entry var videoPlayback = VideoPlayback()
}
