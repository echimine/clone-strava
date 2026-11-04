import Foundation
import Testing
@testable import StravaClone

struct ProfileUpdateTests {
    private let today = CalendarDay(year: 2026, month: 11, day: 4)

    private func validate(_ change: (inout EditableProfile) -> Void) -> Result<ProfileUpdate, ProfileUpdate.Invalid> {
        var profile = EditableProfile(firstName: "Eliott", lastName: "Chiminello")
        change(&profile)
        return ProfileUpdate.validate(profile, today: today)
    }

    @Test func trimsTheTextsAndSendsAnEmptyCountryWhenNoneIsChosen() throws {
        let update = try validate {
            $0.bio = "  Grimpeur \n"
            $0.city = " Annecy "
        }.get()

        #expect(update.bio == "Grimpeur")
        #expect(update.city == "Annecy")
        #expect(update.countryCode == "")
    }

    @Test func refusesAnInvalidName() {
        #expect(validate { $0.lastName = "  " } == .failure(.name))
    }

    @Test func refusesTooLongTexts() {
        #expect(validate { $0.bio = String(repeating: "a", count: 301) } == .failure(.bio))
        #expect(validate { $0.city = String(repeating: "a", count: 101) } == .failure(.city))
    }

    @Test func refusesAnAthleteUnder15ToTheDay() {
        #expect(validate { $0.birthDate = CalendarDay(year: 2011, month: 11, day: 5) } == .failure(.tooYoung))
        #expect((try? validate { $0.birthDate = CalendarDay(year: 2011, month: 11, day: 4) }.get()) != nil)
    }

    @Test func refusesAWeightOutOfRange() {
        #expect(validate { $0.weightKg = 19.9 } == .failure(.weight))
        #expect(validate { $0.weightKg = 301 } == .failure(.weight))
        #expect((try? validate { $0.weightKg = 59.5 }.get())?.weightKg == 59.5)
    }

    @Test func readsAFrenchWeight() {
        #expect(EditProfileFormat.weightKg(from: "59,5") == .some(59.5))
        #expect(EditProfileFormat.weightKg(from: " ") == .some(nil))
        #expect(EditProfileFormat.weightKg(from: "abc") == nil)
        #expect(EditProfileFormat.weight(59) == "59")
    }

    @Test func showsTheCountryAndBirthDateInFrench() {
        #expect(EditProfileFormat.country("FR") == "FRANCE")
        #expect(EditProfileFormat.birthDate(CalendarDay(year: 2006, month: 5, day: 2)) == "2 mai 2006")
    }
}
