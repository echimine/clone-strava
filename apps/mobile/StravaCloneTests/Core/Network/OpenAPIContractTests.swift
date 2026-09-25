import Foundation
import Testing
@testable import StravaClone

/// Contract tests on the types swift-openapi-generator derives from the API's
/// Zod schemas (ADR-026). If a field is renamed/removed/retyped on the API side,
/// `pnpm mobile:sync-openapi` changes openapi.json, the plugin regenerates the
/// types, and either this file stops compiling or an expectation fails.
struct OpenAPIContractTests {
    /// Same date strategy as `APIClient`, so the check matches what the app sends.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// A payload `POST /v1/activities` accepts (`createActivityRequestSchema`,
    /// packages/contracts).
    private let createActivityJSON = Data("""
    {
      "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "sportTypeCode": "run",
      "title": "Sortie du matin",
      "description": "Bords de Seine",
      "startedAt": "2026-09-25T07:00:00Z",
      "endedAt": "2026-09-25T07:45:00Z",
      "visibility": "followers",
      "isManual": false,
      "distanceM": 8200.5,
      "movingTimeS": 2580,
      "elapsedTimeS": 2700,
      "elevationGainM": 42
    }
    """.utf8)

    @Test func createActivityRequestDecodesAnAPIPayload() throws {
        let dto = try decoder.decode(Components.Schemas.CreateActivityRequestDto.self, from: createActivityJSON)

        #expect(dto.id == "7c9e6679-7425-40de-944b-e07fc1f90ae7")
        #expect(dto.sportTypeCode == "run")
        #expect(dto.title == "Sortie du matin")
        #expect(dto.description == "Bords de Seine")
        #expect(dto.visibility.rawValue == "followers")
        #expect(dto.isManual == false)
        #expect(dto.distanceM == 8200.5)
        #expect(dto.movingTimeS == 2580)
        #expect(dto.elapsedTimeS == 2700)
        #expect(dto.elevationGainM == 42)
        #expect(dto.endedAt.timeIntervalSince(dto.startedAt) == 45 * 60)
    }

    @Test func createActivityRequestEncodesTheKeysTheAPIExpects() throws {
        let dto = try decoder.decode(Components.Schemas.CreateActivityRequestDto.self, from: createActivityJSON)
        let encoded = try encoder.encode(dto)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(Set(object.keys) == [
            "id", "sportTypeCode", "title", "description", "startedAt", "endedAt",
            "visibility", "isManual", "distanceM", "movingTimeS", "elapsedTimeS", "elevationGainM",
        ])
        #expect(object["startedAt"] as? String == "2026-09-25T07:00:00Z")
        #expect(object["visibility"] as? String == "followers")
    }

    @Test func createActivityRequestRejectsAPayloadMissingARequiredField() {
        let missingTitle = Data("""
        {
          "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
          "sportTypeCode": "run",
          "startedAt": "2026-09-25T07:00:00Z",
          "endedAt": "2026-09-25T07:45:00Z",
          "visibility": "public",
          "isManual": true
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try decoder.decode(Components.Schemas.CreateActivityRequestDto.self, from: missingTitle)
        }
    }
}
