import Foundation

/// Normalized API error: repositories only see these cases (ADR-008 §5 for handling).
/// `http` carries the raw response body so a repository can read a server-provided
/// error code/message (e.g. Better Auth's `{ code, message }`, ADR-022) instead of
/// guessing what went wrong from the status code alone.
enum APIError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    case http(status: Int, body: Data?)
    case decoding
    case transport(String)
}

/// Answer of a call whose success has no body (`204 No Content`, e.g. a `DELETE`), or
/// whose body the caller ignores: it is never decoded.
struct NoContent: Decodable, Equatable, Sendable {}

/// REST client for the platform API, URLSession + async/await (ADR-006).
struct APIClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let authSession: AuthSession

    private struct EmptyBody: Encodable {}

    /// The API writes ISO 8601 with milliseconds (`toISOString()`), which `.iso8601`
    /// alone rejects: accept both forms.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(value, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(value)")
        }
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

    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws(APIError) -> Response {
        try await send(method: "GET", path: path, query: query, body: EmptyBody?.none)
    }

    /// Body-less call with another verb (e.g. `PUT`/`DELETE` on a sub-resource).
    func send<Response: Decodable>(method: String, path: String) async throws(APIError) -> Response {
        try await send(method: method, path: path, body: EmptyBody?.none)
    }

    func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body?
    ) async throws(APIError) -> Response {
        let (response, _): (Response, HTTPURLResponse) = try await sendWithHeaders(
            method: method,
            path: path,
            query: query,
            body: body
        )
        return response
    }

    /// Same as `send`, but also returns the raw HTTP response so a caller can read
    /// response headers (e.g. Better Auth's `set-auth-token`, ADR-022) — everyone else
    /// should keep using `send`, which discards it.
    func sendWithHeaders<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body?
    ) async throws(APIError) -> (Response, HTTPURLResponse) {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
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
        default: throw .http(status: http.statusCode, body: data)
        }

        if Response.self == NoContent.self, let empty = NoContent() as? Response {
            return (empty, http)
        }
        do {
            return (try Self.decoder.decode(Response.self, from: data), http)
        } catch {
            throw .decoding
        }
    }
}
