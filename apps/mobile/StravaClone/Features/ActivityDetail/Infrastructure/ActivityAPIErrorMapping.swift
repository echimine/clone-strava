import Foundation

/// The errors the Activity detail's API adapters throw (detail, kudos, comments), built from an
/// `APIError` in one place. Their cases witness the requirements.
protocol ActivityAPIErrorMapping: Error {
    static var offline: Self { get }
    static var unauthorized: Self { get }
    /// `404`: unknown, deleted or no longer visible.
    static var notFound: Self { get }
    static var network: Self { get }
    /// Any other answer, with the machine-readable code of the API's error envelope (ADR-009).
    static func server(code: String?) -> Self
}

extension ActivityAPIErrorMapping {
    /// - Parameter rejected: a dedicated error for some statuses (e.g. an edit's `422`); any
    ///   other status is `server(code:)`.
    init(_ error: APIError, rejected: (_ status: Int, _ code: String?) -> Self? = { _, _ in nil }) {
        switch error {
        case .offline: self = .offline
        case .unauthorized: self = .unauthorized
        case .http(404, _): self = .notFound
        case .http(let status, let body):
            let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
            self = rejected(status, code) ?? .server(code: code)
        case .decoding: self = .server(code: nil)
        case .transport: self = .network
        }
    }
}

/// `{ "error": { "code", "message", "details"? } }` (ADR-009).
private struct ErrorEnvelope: Decodable {
    struct Body: Decodable { let code: String }
    let error: Body
}

extension ActivityDetailError: ActivityAPIErrorMapping {}
extension ActivityCommentError: ActivityAPIErrorMapping {}
