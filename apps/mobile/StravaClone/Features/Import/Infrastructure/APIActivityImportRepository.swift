import Foundation

/// `APIClient` adapter of `ActivityImportRepository` (ADR-028 §3), plus the direct `PUT`
/// to the bucket through the pre-signed URL (ADR-001: files never go through the API).
struct APIActivityImportRepository: ActivityImportRepository {
    let apiClient: APIClient

    private static let basePath = "/v1/activity-imports"

    private struct CreateBody: Encodable {
        let id: UUID
        let format: String
        let fileName: String
        let sizeBytes: Int
        let sportTypeCode: String?
        let title: String?
        let visibility: String?
    }

    private struct ImportDTO: Decodable {
        let id: UUID
        let format: ImportFormat
        let fileName: String
        let status: ImportStatus
        let activityId: String?
        let error: String?

        var model: ActivityImport {
            ActivityImport(id: id, format: format, fileName: fileName, status: status, activityId: activityId, errorCode: error)
        }
    }

    private struct UploadDTO: Decodable {
        let uploadUrl: URL
        let expiresAt: String

        var model: UploadTarget {
            UploadTarget(url: uploadUrl, expiresAt: Self.parseDate(expiresAt) ?? .now.addingTimeInterval(900))
        }

        /// The API writes ISO 8601 with milliseconds, which `.iso8601` decoding rejects.
        private static func parseDate(_ value: String) -> Date? {
            try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
    }

    private struct CreateResponse: Decodable {
        let `import`: ImportDTO
        let upload: UploadDTO?
    }

    private struct CompleteResponse: Decodable {
        let `import`: ImportDTO
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    func create(id: UUID, file: ImportFile, options: ImportOptions) async throws(ImportError)
        -> (import: ActivityImport, upload: UploadTarget?)
    {
        let body = CreateBody(
            id: id,
            format: file.format.rawValue,
            fileName: file.fileName,
            sizeBytes: file.sizeBytes,
            sportTypeCode: options.sport?.rawValue,
            title: options.title,
            visibility: options.visibility?.rawValue
        )
        let response: CreateResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: Self.basePath, body: body)
        }
        return (response.import.model, response.upload?.model)
    }

    func renewUploadURL(id: UUID) async throws(ImportError) -> UploadTarget {
        let response: UploadDTO = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "\(Self.basePath)/\(id.uuidString.lowercased())/upload-url", body: String?.none)
        }
        return response.model
    }

    func upload(file: ImportFile, to target: UploadTarget) async throws(ImportError) {
        var request = URLRequest(url: target.url)
        request.httpMethod = "PUT"
        // Must match the content type the URL was signed with (ADR-028 §3).
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let response: URLResponse
        do {
            (_, response) = try await apiClient.session.upload(for: request, fromFile: file.localURL)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw .offline
        } catch {
            throw .network
        }
        switch (response as? HTTPURLResponse)?.statusCode {
        case .some(200..<300): return
        case .some(403): throw .uploadURLExpired
        default: throw .server(code: "upload_failed")
        }
    }

    func complete(id: UUID) async throws(ImportError) -> ActivityImport {
        let response: CompleteResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "\(Self.basePath)/\(id.uuidString.lowercased())/complete", body: String?.none)
        }
        return response.import.model
    }

    func fetch(id: UUID) async throws(ImportError) -> ActivityImport {
        let response: ImportDTO = try await call { () async throws(APIError) in
            try await apiClient.get("\(Self.basePath)/\(id.uuidString.lowercased())")
        }
        return response.model
    }

    /// Maps the normalized `APIError` onto the import's errors.
    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(ImportError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline: throw .offline
            case .unauthorized: throw .unauthorized
            case .http(429, _): throw .rateLimited
            case .http(_, let body):
                let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
                throw .server(code: code)
            case .decoding: throw .server(code: nil)
            case .transport: throw .network
            }
        }
    }
}
