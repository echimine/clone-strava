import Foundation

/// `ActivityServer` over the API (`APIClient`, types generated from openapi.json, ADR-026 §5)
/// and the bucket's pre-signed `PUT` (ADR-019 §1-4, ADR-031 §13, §14).
struct APIActivityServer: ActivityServer {
    private typealias CreateRequest = Components.Schemas.CreateActivityRequestDto
    private typealias CreateResponse = Components.Schemas.CreateActivityResponseDto_Output
    private typealias UploadURLResponse = Components.Schemas.RenewUploadUrlResponseDto_Output
    private typealias DetailResponse = Components.Schemas.ActivityDetailDto_Output

    /// Signed into the URL by the API (`ACTIVITY_TRACE_CONTENT_TYPE`).
    static let traceContentType = "application/gzip"

    let apiClient: APIClient
    /// Regular session for the trace: no background session (ADR-031 §14).
    var uploadSession: URLSession = .shared

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    func create(_ activity: LocalActivity) async throws(ActivityServerError) -> ActivityCreation {
        guard let visibility = CreateRequest.visibilityPayload(rawValue: activity.visibility.rawValue) else {
            throw .refused(code: "validation_error")
        }
        let body = CreateRequest(
            id: activity.id.description,
            sportTypeCode: activity.sport.code,
            title: activity.title,
            startedAt: activity.startedAt,
            endedAt: activity.endedAt,
            visibility: visibility,
            isManual: false,
            distanceM: activity.distance.meters,
            movingTimeS: activity.movingTimeS,
            elapsedTimeS: activity.elapsedTimeS
        )
        let response: CreateResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "/v1/activities", body: body)
        }
        guard let upload = response.upload else { return .alreadyProcessing }
        return .awaitingTrace(try Self.target(url: upload.uploadUrl, expiresAt: upload.expiresAt))
    }

    func renewUploadURL(for id: ActivityID) async throws(ActivityServerError) -> TraceUploadTarget {
        let response: UploadURLResponse
        do {
            response = try await call { () async throws(APIError) in
                try await apiClient.send(method: "POST", path: "/v1/activities/\(id)/upload-url")
            }
        } catch .refused(let code) where code == "not_pending" || code == "http_409" {
            throw .notPending
        }
        return try Self.target(url: response.uploadUrl, expiresAt: response.expiresAt)
    }

    func uploadTrace(_ data: Data, to target: TraceUploadTarget) async throws(ActivityServerError) {
        var request = URLRequest(url: target.url)
        request.httpMethod = "PUT"
        request.setValue(Self.traceContentType, forHTTPHeaderField: "Content-Type")
        let response: URLResponse
        do {
            (_, response) = try await uploadSession.upload(for: request, from: data)
        } catch {
            throw .offline
        }
        guard let http = response as? HTTPURLResponse else { throw .offline }
        switch http.statusCode {
        case 200 ..< 300: return
        case 403: throw .uploadURLExpired
        case 500...: throw .unavailable
        default: throw .refused(code: "upload_\(http.statusCode)")
        }
    }

    func complete(_ id: ActivityID) async throws(ActivityServerError) {
        do {
            let _: NoContent = try await call { () async throws(APIError) in
                try await apiClient.send(method: "POST", path: "/v1/activities/\(id)/complete")
            }
        } catch .refused("trace_missing") {
            throw .traceMissing
        }
    }

    func status(of id: ActivityID) async throws(ActivityServerError) -> RemoteActivityStatus {
        let response: DetailResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/activities/\(id)")
        }
        switch response.processingStatus {
        case .pending: return .pending
        case .processing: return .processing
        case .processed: return .processed
        case .failed: return .failed(reason: response.processingError?.rawValue)
        }
    }

    func delete(_ id: ActivityID) async throws(ActivityServerError) {
        do {
            let _: NoContent = try await call { () async throws(APIError) in
                try await apiClient.send(method: "DELETE", path: "/v1/activities/\(id)")
            }
        } catch .refused(let code) where code == "not_found" || code == "http_404" {
            return
        }
    }

    private static func target(url: String, expiresAt: Date) throws(ActivityServerError) -> TraceUploadTarget {
        guard let url = URL(string: url) else { throw .unavailable }
        return TraceUploadTarget(url: url, expiresAt: expiresAt)
    }

    /// Maps `APIError` onto the response table: the server's code when it gives one,
    /// `http_<status>` otherwise.
    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(ActivityServerError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline, .transport: throw .offline
            case .unauthorized: throw .unauthorized
            case .http(let status, _) where status >= 500: throw .unavailable
            case .http(let status, let body):
                let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
                throw .refused(code: code ?? "http_\(status)")
            case .decoding: throw .unavailable
            }
        }
    }
}
