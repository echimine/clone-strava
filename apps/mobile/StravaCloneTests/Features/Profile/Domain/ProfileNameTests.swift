import Testing
@testable import StravaClone

struct ProfileNameTests {
    @Test func trimsEachPart() throws {
        let name = try #require(ProfileName(firstName: "  Camille ", lastName: "\tMartin\n"))
        #expect(name.firstName == "Camille")
        #expect(name.lastName == "Martin")
        #expect(name.displayName == "Camille Martin")
    }

    @Test func eachPartNeedsOneToFiftyCharacters() {
        #expect(ProfileName(firstName: "   ", lastName: "Martin") == nil)
        #expect(ProfileName(firstName: "Camille", lastName: "") == nil)
        #expect(ProfileName(firstName: String(repeating: "a", count: 50), lastName: "Martin") != nil)
        #expect(ProfileName(firstName: String(repeating: "a", count: 51), lastName: "Martin") == nil)
    }

    @Test func theSheetStartsFromTheShownName() {
        #expect(ProfileName.parts(of: "Camille Martin") == ("Camille", "Martin"))
        #expect(ProfileName.parts(of: "Jean Pierre de la Tour") == ("Jean", "Pierre de la Tour"))
        #expect(ProfileName.parts(of: "Camille") == ("Camille", ""))
        #expect(ProfileName.parts(of: "") == ("", ""))
    }
}
