import Foundation

/// The person's answer to the Measurement consent (ADR-035 §8): kept on this phone, per device,
/// not tied to the account, so it survives sign-out. No answer yet means a first launch.
enum MeasurementConsent: String, Sendable {
    case accepted
    case refused
}

/// Where the Measurement consent is kept on the phone.
protocol MeasurementConsentPreferences: Sendable {
    /// `nil` until the person answers.
    var consent: MeasurementConsent? { get }
    func remember(_ consent: MeasurementConsent)
}
