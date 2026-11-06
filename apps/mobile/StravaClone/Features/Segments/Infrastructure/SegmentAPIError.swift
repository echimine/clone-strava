import Foundation

/// The one translation of the API's answers into `SegmentError`, for every adapter of the
/// feature (ADR-039 §12): `{ error: { code, existing?, details? } }`.
enum SegmentAPIError {
    private struct Envelope: Decodable {
        struct Body: Decodable {
            let code: String
            let existing: Ref?
            let details: [Detail]?
        }

        struct Ref: Decodable {
            let id: String
            let name: String
        }

        struct Detail: Decodable {
            let message: String
        }

        let error: Body
    }

    /// Runs `operation`, its `APIError` told as a `SegmentError`.
    static func call<T>(_ operation: () async throws(APIError) -> T) async throws(SegmentError) -> T {
        do {
            return try await operation()
        } catch {
            throw map(error)
        }
    }

    static func map(_ error: APIError) -> SegmentError {
        switch error {
        case .offline: return .offline
        case .unauthorized: return .unauthorized
        case .decoding: return .server
        case .transport: return .network
        case .http(let status, let body):
            let envelope = body.flatMap { try? JSONDecoder().decode(Envelope.self, from: $0) }?.error
            switch (status, envelope?.code) {
            case (404, _): return .notFound
            case (403, "premium_required"): return .premiumRequired
            case (409, "has_other_efforts"): return .hasOtherEfforts
            case (409, "duplicate"):
                guard let existing = envelope?.existing else { return .invalid(code: "duplicate") }
                return .duplicate(SegmentRef(id: existing.id, name: existing.name))
            case (429, "quota"): return .quota
            case (400, "zone_too_large"): return .zoneTooLarge
            case (422, let code):
                // Every broken rule is in `details`; an invalid name or cursor has none of them.
                let messages = envelope?.details?.map(\.message) ?? [code].compactMap { $0 }
                let violations = messages.compactMap(SegmentRuleViolation.init(rawValue:))
                return violations.isEmpty ? .invalid(code: code) : .rejected(violations)
            case (400 ..< 500, let code): return .invalid(code: code)
            default: return .server
            }
        }
    }
}
