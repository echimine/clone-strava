import Foundation
import Testing
@testable import StravaClone

/// The six questions of the Onboarding and its draft (ADR-035 §1, §5), through `OnboardingStore`
/// over the GRDB draft of an in-memory database.
@MainActor
struct OnboardingStoreTests {
    /// "Today" for every test: 2 November 2026.
    private let today = CalendarDay(year: 2026, month: 11, day: 2)

    private func makeStore(database: AppDatabase? = nil) throws -> OnboardingStore {
        let today = today
        return OnboardingStore(
            drafts: GRDBOnboardingDraftRepository(database: try database ?? AppDatabase.inMemory()),
            today: { today }
        )
    }

    /// A store on the screen `step`, every earlier question answered.
    private func makeStore(at step: OnboardingStep, database: AppDatabase? = nil) async throws -> OnboardingStore {
        let store = try makeStore(database: database)
        await store.load()
        while store.step != step {
            switch store.step {
            case .name:
                store.answers.firstName = "Camille"
                store.answers.lastName = "Martin"
            case .birthDate: store.answers.birthDate = CalendarDay(year: 1994, month: 5, day: 17)
            case .gender: store.answers.gender = .female
            case .sports: store.toggle(.ride)
            case .level: store.answers.level = .intermediate
            default: break
            }
            #expect(store.canContinue, "Stuck on \(store.step)")
            await store.next()
        }
        return store
    }

    @Test func bothNamesAreRequired() async throws {
        let store = try makeStore()
        await store.load()
        #expect(store.step == .name)
        #expect(!store.canContinue)

        store.answers.firstName = "Camille"
        #expect(!store.canContinue)

        store.answers.lastName = "   "
        #expect(!store.canContinue)

        store.answers.lastName = "Martin"
        #expect(store.canContinue)
    }

    @Test func theMinimumAgeIsFifteenToTheDay() async throws {
        let store = try await makeStore(at: .birthDate)
        #expect(!store.canContinue)
        #expect(!store.isTooYoung)

        store.answers.birthDate = CalendarDay(year: 2011, month: 11, day: 3)
        #expect(!store.canContinue)
        #expect(store.isTooYoung)

        store.answers.birthDate = CalendarDay(year: 2011, month: 11, day: 2)
        #expect(store.canContinue)
        #expect(!store.isTooYoung)
    }

    @Test func theBirthDateWheelStartsThirtyYearsAgo() async throws {
        let store = try await makeStore(at: .birthDate)

        store.unfoldBirthDateWheel()
        #expect(store.answers.birthDate == CalendarDay(year: 1996, month: 11, day: 2))

        store.answers.birthDate = CalendarDay(year: 1980, month: 1, day: 9)
        store.unfoldBirthDateWheel()
        #expect(store.answers.birthDate == CalendarDay(year: 1980, month: 1, day: 9))
    }

    @Test func aGenderIsRequired() async throws {
        let store = try await makeStore(at: .gender)
        #expect(!store.canContinue)

        store.answers.gender = .undisclosed
        #expect(store.canContinue)
    }

    @Test func atLeastOneSportInTheOrderPicked() async throws {
        let store = try await makeStore(at: .sports)
        #expect(store.sportChoices == [.run, .ride, .swim, .walk, .hike])
        #expect(!store.canContinue)

        store.toggle(.hike)
        store.toggle(.run)
        store.toggle(.swim)
        store.toggle(.run)
        #expect(store.answers.sports == [.hike, .swim])
        #expect(store.canContinue)

        store.toggle(.hike)
        store.toggle(.swim)
        #expect(!store.canContinue)
    }

    @Test func goalsAreOptionalAndTheButtonSaysSkip() async throws {
        let store = try await makeStore(at: .goals)
        #expect(store.canContinue)
        #expect(store.continueTitle == "Passer")

        store.toggle(.trainForEvent)
        store.toggle(.discoverRoutes)
        #expect(store.continueTitle == "Continuer")
        #expect(store.answers.goals == [.trainForEvent, .discoverRoutes])

        store.toggle(.trainForEvent)
        store.toggle(.discoverRoutes)
        #expect(store.continueTitle == "Passer")
        await store.next()
        #expect(store.step == .level)
        #expect(store.answers.goals == [])
    }

    @Test func aLevelIsRequired() async throws {
        let store = try await makeStore(at: .level)
        #expect(!store.canContinue)

        store.answers.level = .advanced
        #expect(store.canContinue)
        await store.next()
        #expect(store.step == .showcase)
    }

    @Test func eachStepIsSavedAndResumedAfterARelaunch() async throws {
        let database = try AppDatabase.inMemory()
        let store = try makeStore(database: database)
        await store.load()
        store.answers.firstName = " Camille "
        store.answers.lastName = "Martin"
        await store.next()
        store.answers.birthDate = CalendarDay(year: 1994, month: 2, day: 28)
        await store.next()
        store.answers.gender = .nonBinary
        await store.next()
        store.toggle(.hike)
        store.toggle(.run)
        await store.next()
        store.toggle(.health)
        store.toggle(.compete)
        await store.next()
        store.answers.level = .professional
        // The app is killed on the level screen, its choice not confirmed.

        let relaunched = try makeStore(database: database)
        await relaunched.load()

        #expect(relaunched.step == .level)
        var expected = OnboardingAnswers()
        expected.firstName = " Camille "
        expected.lastName = "Martin"
        expected.birthDate = CalendarDay(year: 1994, month: 2, day: 28)
        expected.gender = .nonBinary
        expected.sports = [.hike, .run]
        expected.goals = [.health, .compete]
        #expect(relaunched.answers == expected)
    }

    @Test func goingBackIsSavedButNotOfferedOnTheFirstScreen() async throws {
        let database = try AppDatabase.inMemory()
        let store = try await makeStore(at: .gender, database: database)
        #expect(store.canGoBack)

        await store.back()
        #expect(store.step == .birthDate)
        await store.back()
        #expect(store.step == .name)
        #expect(!store.canGoBack)
        await store.back()
        #expect(store.step == .name)

        let relaunched = try makeStore(database: database)
        await relaunched.load()
        #expect(relaunched.step == .name)
        #expect(relaunched.answers.birthDate == CalendarDay(year: 1994, month: 5, day: 17))
    }

    @Test func createMyAccountOpensTheAccountScreenWithTheFullName() async throws {
        let store = try makeStore()
        await store.load()
        store.answers.firstName = "  Camille "
        store.answers.lastName = " Martin"
        while store.step != .personalizing {
            switch store.step {
            case .birthDate: store.answers.birthDate = CalendarDay(year: 1994, month: 5, day: 17)
            case .gender: store.answers.gender = .female
            case .sports: store.toggle(.run)
            case .level: store.answers.level = .beginner
            default: break
            }
            await store.next()
        }

        await store.next()

        #expect(store.step == .account)
        #expect(store.accountName == "Camille Martin")
    }

    @Test func withoutADraftTheOnboardingStartsAtTheName() async throws {
        let store = try makeStore()
        await store.load()

        #expect(store.step == .name)
        #expect(store.answers == OnboardingAnswers())
    }

    // MARK: Opened by "Se connecter" on an account just created (ADR-035 §1)

    @Test func withASessionTheOnboardingStartsAtTheFirstQuestionWithTheSavedAnswers() async throws {
        let database = try AppDatabase.inMemory()
        _ = try await makeStore(at: .account, database: database)
        let today = today

        let store = OnboardingStore(
            drafts: GRDBOnboardingDraftRepository(database: database),
            today: { today },
            finishWithSession: {}
        )
        await store.load()

        #expect(store.step == .name)
        #expect(store.answers.firstName == "Camille")
    }

    @Test func withASessionCreateMyAccountFinishesWithoutTheAccountScreen() async throws {
        let database = try AppDatabase.inMemory()
        let today = today
        let finished = Locked(0)
        let store = OnboardingStore(
            drafts: GRDBOnboardingDraftRepository(database: database),
            today: { today },
            finishWithSession: { finished.value += 1 }
        )
        await store.load()
        store.answers.firstName = "Camille"
        store.answers.lastName = "Martin"
        while store.step != .personalizing {
            switch store.step {
            case .birthDate: store.answers.birthDate = CalendarDay(year: 1994, month: 5, day: 17)
            case .gender: store.answers.gender = .female
            case .sports: store.toggle(.run)
            case .level: store.answers.level = .beginner
            default: break
            }
            await store.next()
        }

        await store.next()

        #expect(finished.value == 1)
        #expect(store.step == .personalizing)
        #expect(try await GRDBOnboardingDraftRepository(database: database).load()?.answers == store.answers)
    }
}
