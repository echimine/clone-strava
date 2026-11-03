import Foundation

/// Property values of the Avatar events (ADR-037 §13), mirrored in
/// `packages/contracts/src/analytics/catalog.ts` (`APP_ANALYTICS_EVENTS`).
extension AnalyticsEvent {
    /// Where the photo came from.
    enum AvatarSource: String, Sendable {
        case camera, library
    }

    /// Which screen opened the photo menu.
    enum AvatarEntry: String, Sendable {
        /// A tap on my own avatar in the profile header.
        case profile
        /// "Modifier la photo" in "Modifier le profil".
        case editProfile = "edit_profile"
        /// "Ajoute une photo de profil", before the Paywall.
        case onboarding
    }

    /// Why the Avatar was not stored.
    enum AvatarUploadFailure: String, Sendable {
        /// No network when "Choisir" was tapped, or lost on the way.
        case offline
        /// The request failed in transit.
        case network
        /// The API or the bucket refused the file (`409 avatar_missing`, `avatar_too_large`, a
        /// `403` signature mismatch).
        case rejected
        /// Any other server answer, or the session expired.
        case server
        /// The photo could not be turned into a JPEG.
        case encoding
    }
}
