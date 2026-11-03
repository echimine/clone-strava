import Foundation
import Testing
@testable import StravaClone

/// One video plays at a time in the app (ADR-037 §10): the last video slide to become the
/// current slide of a visible carousel, until it leaves.
@MainActor
struct VideoPlaybackTests {
    private let first = UUID()
    private let second = UUID()

    @Test func nothingPlaysAtFirst() {
        #expect(VideoPlayback().playing == nil)
    }

    @Test func theCurrentVideoPlays() {
        let playback = VideoPlayback()

        playback.claim(first)

        #expect(playback.playing == first)
    }

    @Test func aNewCurrentVideoStopsThePreviousOne() {
        let playback = VideoPlayback()

        playback.claim(first)
        playback.claim(second)

        #expect(playback.playing == second)
    }

    @Test func aVideoThatLeavesHandsBackToTheOneStillShown() {
        let playback = VideoPlayback()
        playback.claim(first)
        playback.claim(second)

        playback.release(second)

        #expect(playback.playing == first)
    }

    @Test func releasingAVideoThatDoesNotPlayChangesNothing() {
        let playback = VideoPlayback()
        playback.claim(first)
        playback.claim(second)

        playback.release(first)

        #expect(playback.playing == second)
        playback.release(second)
        #expect(playback.playing == nil)
    }

    @Test func claimingAgainBringsAVideoBackOnTop() {
        let playback = VideoPlayback()
        playback.claim(first)
        playback.claim(second)

        playback.claim(first)

        #expect(playback.playing == first)
        playback.release(first)
        #expect(playback.playing == second)
    }
}
