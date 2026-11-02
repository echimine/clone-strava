import Foundation
import Testing
@testable import StravaClone

/// The Measurement consent (ADR-035 §8): the sheet of the first launch, then the
/// "Mesure d'audience" switch of the "Confidentialité" section, through `MeasurementConsentStore`.
@MainActor
struct MeasurementConsentStoreTests {
    struct Harness {
        let store: MeasurementConsentStore
        let preferences: InMemoryConsentPreferences
        let analytics: FakeAnalyticsClient
        let sleeper: ManualSleeper
    }

    private func makeHarness(
        preferences: InMemoryConsentPreferences = InMemoryConsentPreferences(),
        signedInUserID: String? = nil
    ) -> Harness {
        let analytics = FakeAnalyticsClient()
        let sleeper = ManualSleeper()
        let store = MeasurementConsentStore(
            preferences: preferences,
            analytics: analytics,
            signedInUserID: { signedInUserID },
            sleep: sleeper.sleep
        )
        return Harness(store: store, preferences: preferences, analytics: analytics, sleeper: sleeper)
    }

    @Test func onTheFirstLaunchTheSheetOpensHalfASecondAfterTheSplash() async {
        let harness = makeHarness()

        let asking = Task { await harness.store.askIfNeeded() }
        #expect(await eventually { harness.sleeper.waiting == 1 })
        #expect(harness.sleeper.requested == [.milliseconds(500)])
        #expect(!harness.store.isAsking)

        harness.sleeper.wakeAll()
        await asking.value
        #expect(harness.store.isAsking)
    }

    @Test(arguments: [MeasurementConsent.accepted, .refused])
    func onceAnsweredTheSheetNeverOpensAgain(consent: MeasurementConsent) async {
        let preferences = InMemoryConsentPreferences(consent: consent)
        let harness = makeHarness(preferences: preferences)

        await harness.store.askIfNeeded()

        #expect(!harness.store.isAsking)
        #expect(harness.sleeper.requested.isEmpty)
    }

    @Test func acceptingOpensTheMeasurementAndIsRememberedForTheNextLaunches() async {
        let harness = makeHarness()
        await harness.openSheet()

        await harness.store.accept()

        #expect(!harness.store.isAsking)
        #expect(harness.analytics.calls == [.optIn])
        #expect(harness.store.isMeasurementEnabled)
        #expect(harness.preferences.consent == .accepted)

        let nextLaunch = makeHarness(preferences: harness.preferences)
        await nextLaunch.store.askIfNeeded()
        #expect(!nextLaunch.store.isAsking)
        #expect(nextLaunch.store.isMeasurementEnabled)
    }

    /// The Welcome waits for an answer before `welcome_viewed` (ADR-035 §8).
    @Test(arguments: [true, false])
    func theConsentIsAnsweredOnceAcceptedOrRefused(accepting: Bool) async {
        let harness = makeHarness()
        await harness.openSheet()
        #expect(!harness.store.hasAnswered)

        if accepting { await harness.store.accept() } else { harness.store.refuse() }

        #expect(harness.store.hasAnswered)
        #expect(makeHarness(preferences: harness.preferences).store.hasAnswered)
    }

    @Test func refusingSendsNothing() async {
        let harness = makeHarness()
        await harness.openSheet()

        harness.store.refuse()

        #expect(!harness.store.isAsking)
        #expect(harness.analytics.calls == [.optOut])
        #expect(harness.analytics.events.isEmpty)
        #expect(!harness.store.isMeasurementEnabled)
        #expect(harness.preferences.consent == .refused)
    }

    @Test func turningTheSwitchOffCutsTheMeasurement() async {
        let harness = makeHarness(preferences: InMemoryConsentPreferences(consent: .accepted), signedInUserID: "u1")
        #expect(harness.store.isMeasurementEnabled)

        await harness.store.setMeasurementEnabled(false)

        #expect(harness.analytics.calls == [.optOut])
        #expect(!harness.store.isMeasurementEnabled)
        #expect(harness.preferences.consent == .refused)
    }

    @Test func turningTheSwitchBackOnOpensTheMeasurementThenIdentifiesTheSession() async {
        let harness = makeHarness(preferences: InMemoryConsentPreferences(consent: .refused), signedInUserID: "u1")
        #expect(!harness.store.isMeasurementEnabled)

        await harness.store.setMeasurementEnabled(true)

        #expect(harness.analytics.calls == [.optIn, .identify(userId: "u1")])
        #expect(harness.store.isMeasurementEnabled)
        #expect(harness.preferences.consent == .accepted)
    }

    @Test func acceptingWithoutASessionIdentifiesNobody() async {
        let harness = makeHarness(signedInUserID: nil)

        await harness.store.accept()

        #expect(harness.analytics.calls == [.optIn])
    }
}

extension MeasurementConsentStoreTests.Harness {
    @MainActor
    func openSheet() async {
        let asking = Task { await store.askIfNeeded() }
        _ = await eventually { sleeper.waiting == 1 }
        sleeper.wakeAll()
        await asking.value
    }
}

/// `MeasurementConsentPreferences` in memory: one instance stands for one phone.
final class InMemoryConsentPreferences: MeasurementConsentPreferences, @unchecked Sendable {
    private let stored: Locked<MeasurementConsent?>

    init(consent: MeasurementConsent? = nil) {
        stored = Locked(consent)
    }

    var consent: MeasurementConsent? { stored.value }

    func remember(_ consent: MeasurementConsent) {
        stored.value = consent
    }
}
