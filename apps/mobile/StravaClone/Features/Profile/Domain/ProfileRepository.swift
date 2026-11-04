import Foundation

/// What the athlete changes on their own account from the Profile tab (ADR-036 §3, §1): the
/// profile "Modifier le profil" edits and "Approuver mes abonnés". Reading a profile goes through
/// Core's `AthleteRepository`.
protocol ProfileRepository: Sendable {
    /// My profile as "Modifier le profil" shows it, private fields included.
    func editableProfile() async throws(AthleteError) -> EditableProfile
    /// Returns the profile's new identity.
    func update(_ update: ProfileUpdate) async throws(AthleteError) -> ActivityAuthor
    /// Returns the server's value of the setting.
    func setApproveFollowers(_ approve: Bool) async throws(AthleteError) -> Bool
}
