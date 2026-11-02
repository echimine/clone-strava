import Foundation

/// `MeasurementConsentPreferences` in `UserDefaults`: per device, untouched by sign-out.
struct UserDefaultsMeasurementConsentPreferences: MeasurementConsentPreferences, @unchecked Sendable {
    private static let key = "analytics.measurementConsent"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var consent: MeasurementConsent? {
        defaults.string(forKey: Self.key).flatMap(MeasurementConsent.init(rawValue:))
    }

    func remember(_ consent: MeasurementConsent) {
        defaults.set(consent.rawValue, forKey: Self.key)
    }

    /// Back to a first launch: UI tests only (`-uiTestResetMeasurementConsent`).
    func forget() {
        defaults.removeObject(forKey: Self.key)
    }
}
