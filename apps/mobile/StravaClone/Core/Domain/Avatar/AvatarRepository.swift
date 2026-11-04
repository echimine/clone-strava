import Foundation

/// Why my Avatar could not be sent or removed (ADR-037 §2).
enum AvatarError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    /// The API or the bucket refused the file, with the API's code when there is one
    /// (`avatar_missing`, `avatar_too_large`).
    case rejected(code: String?)
    /// Any other server answer.
    case server
    case network
}

/// My Avatar on the server (ADR-037 §2). In Core because the Profile and the "Ajoute une
/// photo de profil" screen both change it (ADR-007 rule 5). Implemented over the API in
/// `Core/Avatar`, faked in tests.
protocol AvatarRepository: Sendable {
    /// Sends the JPEG to the bucket and stores it as my Avatar: `POST
    /// /v1/me/avatar/upload-url`, the pre-signed `PUT`, then `PUT /v1/me/avatar`. Returns the
    /// new Avatar's signed URL.
    func upload(_ jpeg: Data) async throws(AvatarError) -> URL?
    /// `DELETE /v1/me/avatar`: I show my initials again.
    func remove() async throws(AvatarError)
}
