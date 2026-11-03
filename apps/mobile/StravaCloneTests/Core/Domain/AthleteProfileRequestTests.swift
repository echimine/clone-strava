import Foundation
import Testing
@testable import StravaClone

struct AthleteProfileRequestTests {
    @Test func anotherAthletesProfileIsPushed() {
        #expect(AthleteProfileRequest.destination(of: "lea", viewerId: "me") == .push(AthleteProfileRequest(id: "lea")))
    }

    @Test func myOwnAvatarOpensTheProfileTab() {
        #expect(AthleteProfileRequest.destination(of: "me", viewerId: "me") == .ownProfile)
    }
}
