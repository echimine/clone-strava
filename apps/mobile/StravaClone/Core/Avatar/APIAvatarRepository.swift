import Foundation

/// `APIClient` adapter of `AvatarRepository` (ADR-037 §2), with the generated OpenAPI types
/// (ADR-026). The JPEG goes straight to the bucket through the pre-signed `PUT`, without the
/// session token; `Content-Type` and `Content-Length` are signed and must match exactly.
struct APIAvatarRepository: AvatarRepository {
    private typealias UploadURLRequest = Components.Schemas.AvatarUploadUrlRequestDto
    private typealias UploadURLResponse = Components.Schemas.AvatarUploadUrlResponseDto_Output
    private typealias SetRequest = Components.Schemas.SetAvatarRequestDto
    private typealias SetResponse = Components.Schemas.SetAvatarResponseDto_Output

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    let apiClient: APIClient

    func upload(_ jpeg: Data) async throws(AvatarError) -> URL? {
        let ticket: UploadURLResponse = try await Self.call { () async throws(APIError) in
            try await apiClient.send(
                method: "POST",
                path: "/v1/me/avatar/upload-url",
                body: UploadURLRequest(sizeBytes: jpeg.count)
            )
        }
        try await put(jpeg, to: ticket.uploadUrl)
        let stored: SetResponse = try await Self.call { () async throws(APIError) in
            try await apiClient.send(method: "PUT", path: "/v1/me/avatar", body: SetRequest(avatarId: ticket.avatarId))
        }
        return stored.athlete.avatarUrl.flatMap(URL.init(string:))
    }

    func remove() async throws(AvatarError) {
        let _: NoContent = try await Self.call { () async throws(APIError) in
            try await apiClient.send(method: "DELETE", path: "/v1/me/avatar")
        }
    }

    private func put(_ jpeg: Data, to uploadURL: String) async throws(AvatarError) {
        guard let url = URL(string: uploadURL) else { throw .server }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(String(jpeg.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = jpeg
        let response: URLResponse
        do {
            (_, response) = try await apiClient.session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw .offline
        } catch {
            throw .network
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return
        case 400..<500: throw .rejected(code: nil)
        default: throw .server
        }
    }

    private static func call<T>(_ operation: () async throws(APIError) -> T) async throws(AvatarError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline: throw .offline
            case .unauthorized: throw .unauthorized
            case .http(let status, let body) where (400..<500).contains(status):
                throw .rejected(code: body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code)
            case .http, .decoding: throw .server
            case .transport: throw .network
            }
        }
    }
}
