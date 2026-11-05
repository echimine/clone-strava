import Testing
@testable import StravaClone

/// The Avatar events (ADR-037 §13), as the Zod catalog names them; never any image data.
struct AvatarAnalyticsEventTests {
    @Test func aChangedAvatarSaysWhereThePhotoCameFromAndWhichScreenOpenedTheMenu() {
        let event = AnalyticsEvent.avatarChanged(source: .camera, entry: .editProfile)

        #expect(event.name == "avatar_changed")
        #expect(event.properties == ["source": "camera", "entry": "edit_profile"])
        #expect(AnalyticsEvent.avatarChanged(source: .library, entry: .onboarding).properties == [
            "source": "library", "entry": "onboarding",
        ])
    }

    @Test func aRemovedAvatarCarriesNothing() {
        #expect(AnalyticsEvent.avatarRemoved.name == "avatar_removed")
        #expect(AnalyticsEvent.avatarRemoved.properties.isEmpty)
    }

    @Test func aFailedUploadCarriesItsReason() {
        let event = AnalyticsEvent.avatarUploadFailed(reason: .rejected)

        #expect(event.name == "avatar_upload_failed")
        #expect(event.properties == ["reason": "rejected"])
    }
}
