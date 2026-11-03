import Foundation

/// How the API answered a Media call, sorted for the failure table of ADR-037 §5.
enum MediaServerError: Error, Equatable, Sendable {
    /// No network, timeout: backoff.
    case offline
    /// 5xx or an unreadable answer: backoff.
    case unavailable
    /// `401`: the session is refreshed, then the call is sent again.
    case unauthorized
    /// `404 activity_not_found`: the Activity is gone, silent abandon.
    case notFound
    /// `409` or `422`, with the API's code (`media_missing`, `media_limit_reached`,
    /// `media_invalid`, `media_id_taken`, `validation_error`…).
    case refused(code: String)
}

/// A pre-signed `PUT` for one file (24 h, `Content-Type` and `Content-Length` signed).
struct MediaUploadTarget: Hashable, Sendable {
    let name: String
    let url: URL
    let expiresAt: Date
}

/// The Media routes of ADR-037 §4, behind a protocol for the queue's tests.
protocol MediaUploadServer: Sendable {
    /// `POST /v1/activities/:id/media/upload-urls` with the Media's full file set: one target
    /// per file, in the request's order. Writes nothing, may be replayed.
    func uploadTargets(for upload: MediaUpload) async throws(MediaServerError) -> [MediaUploadTarget]
    /// `POST /v1/activities/:id/media`: the confirmed Media (`201`, or `200` on a replay).
    func confirm(_ upload: MediaUpload) async throws(MediaServerError) -> ActivityMedia
}

/// `MediaUploadServer` over the API (`APIClient`, generated OpenAPI types, ADR-026).
struct APIMediaUploadServer: MediaUploadServer {
    private typealias URLsRequest = Components.Schemas.MediaUploadUrlsRequestDto
    private typealias URLsResponse = Components.Schemas.MediaUploadUrlsResponseDto_Output
    private typealias FileRequest = Components.Schemas.MediaUploadFile
    private typealias ConfirmRequest = Components.Schemas.ConfirmMediaRequestDto
    private typealias ConfirmResponse = Components.Schemas.ConfirmMediaResponseDto_Output

    let apiClient: APIClient

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    func uploadTargets(for upload: MediaUpload) async throws(MediaServerError) -> [MediaUploadTarget] {
        var files: [FileRequest] = []
        for file in upload.files {
            guard let name = FileRequest.namePayload(rawValue: file.name),
                  let contentType = FileRequest.contentTypePayload(rawValue: file.contentType)
            else { throw .refused(code: "validation_error") }
            files.append(FileRequest(name: name, contentType: contentType, contentLength: file.byteCount))
        }
        let body = URLsRequest(mediaId: Self.id(upload.mediaID), kind: Self.kind(upload.kind), files: files)
        let response: URLsResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "/v1/activities/\(upload.activityID)/media/upload-urls", body: body)
        }
        var targets: [MediaUploadTarget] = []
        for file in response.files {
            guard let url = URL(string: file.uploadUrl) else { throw .unavailable }
            targets.append(MediaUploadTarget(name: file.name.rawValue, url: url, expiresAt: file.expiresAt))
        }
        return targets
    }

    func confirm(_ upload: MediaUpload) async throws(MediaServerError) -> ActivityMedia {
        guard let width = upload.width, let height = upload.height,
              let kind = ConfirmRequest.kindPayload(rawValue: upload.kind.rawValue)
        else { throw .refused(code: "validation_error") }
        // The generated type omits a nil `durationMs`, which the API takes for a photo.
        let body = ConfirmRequest(
            id: Self.id(upload.mediaID),
            kind: kind,
            width: width,
            height: height,
            durationMs: upload.durationMs,
            position: upload.position
        )
        let response: ConfirmResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "/v1/activities/\(upload.activityID)/media", body: body)
        }
        guard let media = response.media.model else { throw .unavailable }
        return media
    }

    private static func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    private static func kind(_ kind: ActivityMedia.Kind) -> URLsRequest.kindPayload {
        switch kind {
        case .photo: .photo
        case .video: .video
        }
    }

    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(MediaServerError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline, .transport: throw .offline
            case .unauthorized: throw .unauthorized
            case .decoding: throw .unavailable
            case .http(let status, _) where status >= 500: throw .unavailable
            case .http(404, _): throw .notFound
            case .http(let status, let body):
                let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
                throw .refused(code: code ?? "http_\(status)")
            }
        }
    }
}
