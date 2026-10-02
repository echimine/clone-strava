import Foundation

/// Failures of the import flow, as the presentation needs them.
enum ImportError: Error, Equatable, Sendable {
    case offline
    case unsupportedFile
    case fileTooLarge
    case unreadableFile
    /// The pre-signed URL expired (`403` from the bucket, ADR-019 §2).
    case uploadURLExpired
    /// `429` (ADR-028 §9).
    case rateLimited
    /// Session expired.
    case unauthorized
    /// Any other server answer, with its machine-readable code when there is one.
    case server(code: String?)
    case network
}
