import Testing
@testable import StravaClone

struct EmailValidationTests {
    @Test(arguments: [
        ("a@b.com", true),
        ("test.user+tag@example.co.uk", true),
        ("", false),
        ("nodomain", false),
        ("missing-at.com", false),
        ("two@@at.com", false),
        ("trailing@dot.", false),
        ("a b@c.com", false),
    ])
    func validity(email: String, expected: Bool) {
        #expect(EmailValidation.isValid(email) == expected)
    }
}
