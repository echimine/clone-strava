import Foundation
import Testing
@testable import StravaClone

/// `AVPlayer` reads a video's pre-signed URL itself (ADR-037 §1): a `403` comes back as the
/// item's error, which asks the screen for fresh URLs like an expired image.
struct VideoURLExpiryTests {
    private func coreMedia(_ code: Int) -> NSError {
        NSError(domain: "CoreMediaErrorDomain", code: code)
    }

    private func avFoundation(underlying: NSError) -> NSError {
        NSError(domain: "AVFoundationErrorDomain", code: -11_850, userInfo: [NSUnderlyingErrorKey: underlying])
    }

    @Test func anHTTP403UnderTheItemsErrorIsAnExpiredURL() {
        #expect(VideoURLExpiry.isExpired(error: avFoundation(underlying: coreMedia(-12_660)), logStatusCodes: []))
    }

    @Test func a403InTheErrorLogIsAnExpiredURL() {
        #expect(VideoURLExpiry.isExpired(error: avFoundation(underlying: coreMedia(-12_000)), logStatusCodes: [403]))
        #expect(VideoURLExpiry.isExpired(error: nil, logStatusCodes: [-12_660]))
    }

    @Test func otherFailuresAreNot() {
        // HTTP 404: the object was deleted, nothing to reload.
        #expect(!VideoURLExpiry.isExpired(error: avFoundation(underlying: coreMedia(-12_938)), logStatusCodes: [404]))
        #expect(!VideoURLExpiry.isExpired(error: URLError(.notConnectedToInternet), logStatusCodes: []))
        #expect(!VideoURLExpiry.isExpired(error: nil, logStatusCodes: []))
    }
}

/// The viewer closes on a swipe down only (ADR-037 §10).
struct MediaViewerSwipeTests {
    @Test func aSwipeDownPastTheThresholdCloses() throws {
        let offset = try #require(MediaViewerSwipe.offset(for: CGSize(width: 10, height: 200)))
        #expect(offset == 200)
        #expect(MediaViewerSwipe.closes(at: offset))
        #expect(!MediaViewerSwipe.closes(at: 100))
    }

    @Test func aSwipeUpNeitherMovesNorCloses() throws {
        let offset = try #require(MediaViewerSwipe.offset(for: CGSize(width: 0, height: -300)))
        #expect(offset == 0)
        #expect(!MediaViewerSwipe.closes(at: offset))
    }

    @Test func aHorizontalSwipeIsThePagers() {
        #expect(MediaViewerSwipe.offset(for: CGSize(width: 200, height: 50)) == nil)
    }
}
