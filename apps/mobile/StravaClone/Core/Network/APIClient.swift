import Foundation

/// Normalized API error: repositories only see these cases (ADR-008 §5 for handling).
enum APIError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    case http(status: Int)
    case decoding
    case transport(String)
}

/// REST client for the platform API, URLSession + async/await (ADR-006).
struct APIClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let authSession: AuthSession

    private struct EmptyBody: Encodable {}

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(baseURL: URL, session: URLSession = .shared, authSession: AuthSession) {
        self.baseURL = baseURL
        self.session = session
        self.authSession = authSession
    }

    func get<Response: Decodable>(_ path: String) async throws(APIError) -> Response {
        try await send(method: "GET", path: path, body: EmptyBody?.none)
    }

    func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body?
    ) async throws(APIError) -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authSession.token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try Self.encoder.encode(body)
            } catch {
                throw .transport("encoding: \(error)")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw .offline
        } catch {
            throw .transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw .transport("not an HTTP response") }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw .unauthorized
        default: throw .http(status: http.statusCode)
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw .decoding
        }
    }
}
