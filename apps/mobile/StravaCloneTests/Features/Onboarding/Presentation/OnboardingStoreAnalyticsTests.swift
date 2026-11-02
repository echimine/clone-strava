import Foundation
import Testing
@testable import StravaClone

/// The Onboarding's part of the getting-started funnel (ADR-035 §8), through `OnboardingStore`
/// over the GRDB draft of an in-memory database: `onboarding_step_viewed` on each screen,
/// `onboarding_completed` on "Créer mon compte", never a name, a birth date or a gender.
@MainActor
struct OnboardingStoreAnalyticsTests {
    private let today = CalendarDay(year: 2026, month: 11, day: 2)

    private func makeStore(
        database: AppDatabase,
        analytics: FakeAnalyticsClient,
        finishWithSession: (@MainActor () -> Void)? = nil
    ) -> OnboardingStore {
        let today = today
        return OnboardingStore(
            drafts: GRDBOnboardingDraftRepository(database: database),
            analytics: analytics,
            today: { today },
            finishWithSession: finishWithSession
        )
    }

    /// Answers the current question the way Camille Martin does, then goes on.
    private func answerAndContinue(_ store: OnboardingStore, goals: [Goal] = [.health, .compete]) async {
        switch store.step {
        case .name:
            store.answers.firstName = "Camille"
            store.answers.lastName = "Martin"
        case .birthDate: store.answers.birthDate = CalendarDay(year: 1994, month: 5, day: 17)
        case .gender: store.answers.gender = .female
        case .sports:
            store.toggle(.run)
            store.toggle(.ride)
        case .goals: goals.forEach(store.toggle)
        case .level: store.answers.level = .intermediate
        default: break
        }
        await store.next()
    }

    private func walk(_ store: OnboardingStore, to step: OnboardingStep, goals: [Goal] = [.health, .compete]) async {
        while store.step != step {
            await answerAndContinue(store, goals: goals)
        }
    }

    @Test func eachScreenUpToTheAccountIsViewedInTurn() async throws {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(database: try AppDatabase.inMemory(), analytics: analytics)

        await store.load()
        await walk(store, to: .account)

        let steps: [AnalyticsEvent.OnboardingScreen] = [
            .name, .birthdate, .gender, .sports, .goals, .level, .showcase, .personalizing,
        ]
        #expect(analytics.events(named: "onboarding_step_viewed") == steps.map {
            .onboardingStepViewed(step: $0, resumed: false)
        })
    }

    @Test func goingBackViewsThePreviousScreenAgain() async throws {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(database: try AppDatabase.inMemory(), analytics: analytics)
        await store.load()
        await walk(store, to: .gender)

        await store.back()

        #expect(analytics.events.last == .onboardingStepViewed(step: .birthdate, resumed: false))
    }

    @Test func aResumedOnboardingMarksOnlyItsFirstScreen() async throws {
        let database = try AppDatabase.inMemory()
        let first = makeStore(database: database, analytics: FakeAnalyticsClient())
        await first.load()
        await walk(first, to: .sports)
        let analytics = FakeAnalyticsClient()
        let resumed = makeStore(database: database, analytics: analytics)

        await resumed.load()
        await answerAndContinue(resumed)

        #expect(analytics.events == [
            .onboardingStepViewed(step: .sports, resumed: true),
            .onboardingStepViewed(step: .goals, resumed: false),
        ])
    }

    @Test func createMyAccountCompletesTheOnboardingWithSortedCodes() async throws {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(database: try AppDatabase.inMemory(), analytics: analytics)
        await store.load()
        await walk(store, to: .personalizing)

        await store.next()

        let completed = try #require(analytics.events(named: "onboarding_completed").only)
        #expect(completed.properties == [
            "sportCodes": "ride,run",
            "goals": "compete,health",
            "goalsCount": 2,
            "level": "intermediate",
        ])
    }

    @Test func skippedGoalsCompleteWithNone() async throws {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(database: try AppDatabase.inMemory(), analytics: analytics)
        await store.load()
        await walk(store, to: .personalizing, goals: [])

        await store.next()

        let completed = try #require(analytics.events(named: "onboarding_completed").only)
        #expect(completed.properties["goals"] == "")
        #expect(completed.properties["goalsCount"] == 0)
    }

    @Test func withASessionCreateMyAccountCompletesTheOnboardingToo() async throws {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(database: try AppDatabase.inMemory(), analytics: analytics, finishWithSession: {})
        await store.load()
        await walk(store, to: .personalizing)

        await store.next()

        #expect(analytics.events(named: "onboarding_completed").count == 1)
    }

    @Test func noEventCarriesTheNameTheBirthDateOrTheGender() async throws {
        let analytics = FakeAnalyticsClient()
        let store = makeStore(database: try AppDatabase.inMemory(), analytics: analytics)
        await store.load()
        await walk(store, to: .personalizing)
        await store.next()

        let personal = ["Camille", "Martin", "1994", "female", "32"]
        for event in analytics.events {
            for (key, value) in event.properties {
                #expect(!["name", "firstName", "lastName", "email", "birthDate", "age", "gender"].contains(key))
                if case .string(let text) = value {
                    #expect(!personal.contains { text.contains($0) }, "\(event.name).\(key) = \(text)")
                }
            }
        }
    }
}

extension Array {
    /// The single element, or `nil` when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
