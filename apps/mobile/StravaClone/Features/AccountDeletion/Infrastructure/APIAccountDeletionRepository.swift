import Foundation

/// `APIClient` adapter of `AccountDeletionRepository`: `GET /v1/me/account-deletion`, `POST
/// /v1/me/account-deletion/code` and `POST /v1/me/account-deletion { code }` (ADR-038 §13).
struct APIAccountDeletionRepository: AccountDeletionRepository {
    private typealias PreviewResponse = Components.Schemas.AccountDeletionPreviewDto_Output

    private struct DeletionBody: Encodable {
        let code: String
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    let apiClient: APIClient

    func appStoreBilled() async throws(AccountDeletionError) -> Bool {
        let response: PreviewResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/me/account-deletion")
        }
        return response.appStoreBilled
    }

    func sendCode() async throws(AccountDeletionError) {
        let _: NoContent = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "/v1/me/account-deletion/code")
        }
    }

    func deleteAccount(code: String) async throws(AccountDeletionError) {
        let _: NoContent = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "/v1/me/account-deletion", body: DeletionBody(code: code))
        }
    }

    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(AccountDeletionError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline: throw .offline
            case .unauthorized: throw .unauthorized
            case .http(let status, let body):
                let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
                switch (status, code) {
                case (403, "admin_cannot_delete_account"): throw .administrator
                case (400, "invalid_code"): throw .invalidCode
                case (400, "code_expired"), (400, "too_many_attempts"): throw .expiredCode
                case (400, _): throw .invalidCode
                default: throw .server
                }
            case .decoding: throw .server
            case .transport: throw .network
            }
        }
    }
}
