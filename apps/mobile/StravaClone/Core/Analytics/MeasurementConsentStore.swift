import Foundation
import Observation

/// The Measurement consent (ADR-035 §8): the sheet over the Welcome on the first launch, then the
/// "Mesure d'audience" switch of the "Confidentialité" section. The answer is kept on the phone
/// (`MeasurementConsentPreferences`) and opens or cuts the `AnalyticsClient`.
@Observable
@MainActor
final class MeasurementConsentStore {
    /// The sheet is shown: no answer yet, half a second after the splash.
    private(set) var isAsking = false
    /// The switch's state: `true` only once "Accepter" was chosen.
    private(set) var isMeasurementEnabled: Bool

    @ObservationIgnored private let preferences: any MeasurementConsentPreferences
    @ObservationIgnored private let analytics: any AnalyticsClient
    /// The signed-in account's id, if any, to identify it once the measurement opens.
    @ObservationIgnored private let signedInUserID: @Sendable () async -> String?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    init(
        preferences: any MeasurementConsentPreferences,
        analytics: any AnalyticsClient,
        signedInUserID: @escaping @Sendable () async -> String?,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.preferences = preferences
        self.analytics = analytics
        self.signedInUserID = signedInUserID
        self.sleep = sleep
        isMeasurementEnabled = preferences.consent == .accepted
    }

    /// Once the splash is gone: on the first launch only, the sheet opens 0.5 s later.
    func askIfNeeded() async {
        guard preferences.consent == nil, !isAsking else { return }
        do { try await sleep(Self.delayAfterSplash) } catch { return }
        guard preferences.consent == nil else { return }
        isAsking = true
    }

    /// "Accepter".
    func accept() async {
        await setMeasurementEnabled(true)
    }

    /// "Refuser": nothing is sent, and nothing else changes in the app.
    func refuse() {
        remember(.refused)
        analytics.optOut()
    }

    /// The "Mesure d'audience" switch. Turned back on, the session (if any) is identified again,
    /// since the SDK ignored it while cut.
    func setMeasurementEnabled(_ enabled: Bool) async {
        guard enabled else { return refuse() }
        remember(.accepted)
        analytics.optIn()
        if let userId = await signedInUserID() {
            analytics.identify(userId: userId)
        }
    }

    static let delayAfterSplash = Duration.milliseconds(500)

    private func remember(_ consent: MeasurementConsent) {
        preferences.remember(consent)
        isMeasurementEnabled = consent == .accepted
        isAsking = false
    }
}
