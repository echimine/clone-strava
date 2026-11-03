import Foundation

/// What the athlete changes on their own account from the Profile tab (ADR-036 §3, §1): the
/// name everyone sees and "Approuver mes abonnés". Reading a profile goes through Core's
/// `AthleteRepository`.
protocol ProfileRepository: Sendable {
    /// Returns the profile's new identity.
    func rename(_ name: ProfileName) async throws(AthleteError) -> ActivityAuthor
    /// Returns the server's value of the setting.
    func setApproveFollowers(_ approve: Bool) async throws(AthleteError) -> Bool
}
