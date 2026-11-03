import CoreGraphics
import Foundation
import Testing
@testable import StravaClone

struct ActivityMediaSlideTests {
    @Test func videoDurationsReadLikeOnStrava() {
        #expect(ActivityMediaSlide.durationLabel(.milliseconds(10_000)) == "0:10")
        #expect(ActivityMediaSlide.durationLabel(.milliseconds(9_400)) == "0:09")
        #expect(ActivityMediaSlide.durationLabel(.milliseconds(65_000)) == "1:05")
        #expect(ActivityMediaSlide.durationLabel(.milliseconds(3_723_000)) == "1:02:03")
    }

    /// A 2048 × 1536 photo filling a 338 × 250 pt slide at 3x (1014 × 750 px): the width sets
    /// the scale, so the longest side needs 1014 px, rounded up to a multiple of 128.
    @Test func aPhotoIsDecodedAtTheSizeItFills() {
        #expect(ActivityMediaSlide.decodePixelSize(width: 2_048, height: 1_536, filling: CGSize(width: 338, height: 250), scale: 3) == 1_024)
    }

    /// A portrait 1536 × 2048 photo in the same slide: 1014 px wide, so 1352 px tall.
    @Test func aPortraitPhotoIsDecodedAtTheSizeItFills() {
        #expect(ActivityMediaSlide.decodePixelSize(width: 1_536, height: 2_048, filling: CGSize(width: 338, height: 250), scale: 3) == 1_408)
    }

    @Test func aPhotoIsNeverDecodedLargerThanItIs() {
        #expect(ActivityMediaSlide.decodePixelSize(width: 800, height: 600, filling: CGSize(width: 393, height: 330), scale: 3) == 800)
    }
}
