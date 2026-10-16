import SwiftUI

/// How far the celebration's background has shrunk into the mini-map (ADR-032 §5, step 5),
/// from its height: 0 full screen, 1 at the mini-map's height. The map's framing and line
/// follow it on every frame of the shrink, so the map lands on the mini-map's look instead of
/// switching to it at once. Pure.
struct CelebrationShrink: Equatable {
    let progress: Double
    private let fullHeight: Double

    /// `fullHeight`: the background's height before the shrink.
    init(height: Double, fullHeight: Double) {
        self.fullHeight = fullHeight
        let span = fullHeight - CelebrationMiniMap.height
        progress = span > 0 ? min(max((fullHeight - height) / span, 0), 1) : 0
    }

    /// The trace's width, from the celebration's to the mini-map's.
    var lineWidth: Double {
        interpolate(6, 4)
    }

    /// The mini-map's start and finish markers fade in.
    var endpointsOpacity: Double {
        progress
    }

    /// The whole outing's framing: full screen, room above the trace and more below it for the
    /// stats; at the mini-map's size, the mini-map's own padding.
    var overviewPadding: EdgeInsets {
        let mini = RecordingTraceMap.overviewPadding
        return EdgeInsets(
            top: interpolate(fullHeight * 0.12, mini.top),
            leading: interpolate(32, mini.leading),
            bottom: interpolate(fullHeight * 0.24, mini.bottom),
            trailing: interpolate(32, mini.trailing)
        )
    }

    private func interpolate(_ full: Double, _ mini: Double) -> Double {
        full + (mini - full) * progress
    }
}
