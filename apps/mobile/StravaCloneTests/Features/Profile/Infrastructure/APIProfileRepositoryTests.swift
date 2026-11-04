import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFeedRepositoryTests`: suites run in parallel.
private final class ProfileURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[(request: URLRequest, body: Data?)]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append((request, request.bodyData))
        let (status, body) = Self.handler.value?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// `URLSession` hands the protocol a stream rather than `httpBody`.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite(.serialized)
struct APIProfileRepositoryTests {
    private let athleteId = "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01"

    private func makeRepository() -> APIProfileRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocolStub.self]
        let authSession = AuthSession(service: "test.profile.\(UUID())")
        authSession.clear()
        ProfileURLProtocolStub.requests.value = []
        return APIProfileRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        ProfileURLProtocolStub.handler.value = { _ in (status, body) }
    }

    private func sentJSON() throws -> NSDictionary? {
        let body = try #require(ProfileURLProtocolStub.requests.value.last?.body)
        return try JSONSerialization.jsonObject(with: body) as? NSDictionary
    }

    @Test func readingMyProfileMapsEveryField() async throws {
        let repository = makeRepository()
        respond(200, #"""
        { "profile": { "firstName": "Eliott", "lastName": "Chiminello", "bio": null, "city": null,
          "country": "FR", "mainSportCode": "ride", "birthDate": "2006-05-02", "gender": "male",
          "weightKg": 59 } }
        """#)

        let profile = try await repository.editableProfile()

        #expect(ProfileURLProtocolStub.requests.value.last?.request.url?.path == "/v1/me/profile")
        #expect(profile == EditableProfile(
            firstName: "Eliott",
            lastName: "Chiminello",
            countryCode: "FR",
            mainSport: .ride,
            birthDate: CalendarDay(year: 2006, month: 5, day: 2),
            gender: .male,
            weightKg: 59
        ))
    }

    @Test func savingPatchesMyProfileAndReturnsTheNewIdentity() async throws {
        let repository = makeRepository()
        respond(200, #"{ "athlete": { "id": "\#(athleteId)", "displayName": "Léa Bernard", "avatarUrl": null } }"#)
        var edited = EditableProfile(firstName: "Léa", lastName: "Bernard", city: "Annecy", gender: .female)
        edited.birthDate = CalendarDay(year: 1990, month: 4, day: 12)
        let update = try ProfileUpdate.validate(edited).get()

        let athlete = try await repository.update(update)

        let request = try #require(ProfileURLProtocolStub.requests.value.last?.request)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/me/profile")
        // Bio and Pays are sent empty, which clears them; no sport nor weight, left as they are.
        #expect(try sentJSON() == [
            "firstName": "Léa", "lastName": "Bernard", "bio": "", "city": "Annecy", "country": "",
            "birthDate": "1990-04-12", "gender": "female",
        ])
        #expect(athlete == ActivityAuthor(id: athleteId, displayName: "Léa Bernard", avatarURL: nil))
    }

    @Test func approvingFollowersPutsTheSettingAndReturnsTheServersValue() async throws {
        let repository = makeRepository()
        respond(200, #"{ "approveFollowers": true }"#)

        let approved = try await repository.setApproveFollowers(true)

        let request = try #require(ProfileURLProtocolStub.requests.value.last?.request)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/me/follow-settings")
        #expect(try sentJSON() == ["approveFollowers": true])
        #expect(approved)
    }

    @Test func aRefusedProfileKeepsTheServersCode() async throws {
        let repository = makeRepository()
        respond(422, #"{ "error": { "code": "validation_error" } }"#)
        let update = try ProfileUpdate.validate(EditableProfile(firstName: "Léa", lastName: "Bernard")).get()

        await #expect(throws: AthleteError.server(code: "validation_error")) {
            _ = try await repository.update(update)
        }
    }
}
