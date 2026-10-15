import Testing
@testable import StravaClone

struct ItinerarySportTests {
    @Test func profilesMatchTheSportCategories() {
        #expect(SportCategory.foot.routingProfile.rawValue == "walking")
        #expect(SportCategory.wheels.routingProfile.rawValue == "cycling")
    }
}
