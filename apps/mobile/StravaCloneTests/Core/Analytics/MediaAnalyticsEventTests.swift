import Testing
@testable import StravaClone

/// The Media events (ADR-037 §13), as the Zod catalog names them; never a `mediaId` or an
/// `activityId`.
struct MediaAnalyticsEventTests {
    @Test func theViewerSaysWhereItWasOpenedWhatAndWhose() {
        let event = AnalyticsEvent.mediaViewerOpened(source: .profileActivities, kind: .video, isOwn: true)

        #expect(event.name == "media_viewer_opened")
        #expect(event.properties == ["source": "profile_activities", "kind": "video", "isOwn": true])
    }

    @Test func theGallerySaysWhoseItIs() {
        let event = AnalyticsEvent.galleryViewed(isOwn: false)

        #expect(event.name == "gallery_viewed")
        #expect(event.properties == ["isOwn": false])
    }
}
