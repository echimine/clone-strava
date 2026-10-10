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

    /// A `GET /v1/feed` answer (`feedResponseSchema`, ADR-029), dates with milliseconds.
    @Test func feedResponseDecodesAnAPIPayload() throws {
        let json = Data("""
        {
          "items": [{
            "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
            "title": "Sortie du matin",
            "sportTypeCode": "run",
            "startedAt": "2026-10-02T12:32:00.000Z",
            "visibility": "public",
            "locationName": null,
            "stats": { "distanceM": 10234.5, "movingTimeS": 3120, "elapsedTimeS": 3300, "elevationGainM": 245 },
            "map": null,
            "author": { "id": "1b4e28ba-2fa1-41d2-883f-0016d3cca427", "displayName": "Camille Martin", "avatarUrl": null },
            "engagement": { "kudosCount": 3, "commentCount": 1, "viewerHasKudoed": false },
            "viewerIsAuthor": true
          }],
          "nextCursor": null
        }
        """.utf8)

        let dto = try APIClient.decoder.decode(Components.Schemas.FeedResponseDto_Output.self, from: json)

        let item = try #require(dto.items.first)
        #expect(item.title == "Sortie du matin")
        #expect(item.locationName == nil)
        #expect(item.stats.distanceM == 10234.5)
        #expect(item.engagement.kudosCount == 3)
        #expect(item.viewerIsAuthor)
    }

    // MARK: Itineraries (ADR-030 §6)

    /// `{ waypoints, legs }` as `POST /v1/itineraries`, `PUT /v1/itineraries/:id` and
    /// `metrics-preview` accept them (`itineraryGeometrySchema`): one `follow`, one `straight` Leg.
    private let geometryJSON = """
      "waypoints": [{ "lat": 45.9, "lon": 6.12 }, { "lat": 45.91, "lon": 6.12 }, { "lat": 45.92, "lon": 6.12 }],
      "legs": [{ "mode": "follow", "polyline6": "_mopvA_cptJ_pR?" }, { "mode": "straight" }]
    """

    private func json(_ fields: String...) -> Data {
        Data("{\(fields.joined(separator: ","))}".utf8)
    }

    /// The keys a request DTO encodes, top level and per Leg.
    private func encodedKeys(_ value: some Encodable) throws -> (top: Set<String>, legs: [Set<String>]) {
        let object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
        let legs = try #require(object["legs"] as? [[String: Any]])
        return (Set(object.keys), legs.map { Set($0.keys) })
    }

    @Test func createItineraryRequestRoundTripsAnAPIPayload() throws {
        let payload = json(#""id": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "name": "Tour du lac", "sportTypeCode": "hike""#, geometryJSON)

        let dto = try decoder.decode(Components.Schemas.CreateItineraryRequestDto.self, from: payload)

        #expect(dto.id == "7c9e6679-7425-40de-944b-e07fc1f90ae7")
        #expect(dto.name == "Tour du lac")
        #expect(dto.sportTypeCode == "hike")
        #expect(dto.waypoints.map(\.lat) == [45.9, 45.91, 45.92])
        #expect(dto.legs == [.case1(.init(mode: .follow, polyline6: "_mopvA_cptJ_pR?")), .case2(.init(mode: .straight))])
        let keys = try encodedKeys(dto)
        #expect(keys.top == ["id", "name", "sportTypeCode", "waypoints", "legs"])
        #expect(keys.legs == [["mode", "polyline6"], ["mode"]])
    }

    @Test func updateItineraryRequestRoundTripsAnAPIPayload() throws {
        let payload = json(#""name": "Tour du lac", "sportTypeCode": "run""#, geometryJSON)

        let dto = try decoder.decode(Components.Schemas.UpdateItineraryRequestDto.self, from: payload)

        #expect(dto.name == "Tour du lac")
        #expect(dto.sportTypeCode == "run")
        #expect(dto.legs.count == 2)
        let keys = try encodedKeys(dto)
        #expect(keys.top == ["name", "sportTypeCode", "waypoints", "legs"])
        #expect(keys.legs == [["mode", "polyline6"], ["mode"]])
    }

    @Test func metricsPreviewRequestRoundTripsAnAPIPayload() throws {
        let dto = try decoder.decode(Components.Schemas.ItineraryMetricsPreviewRequestDto.self, from: json(geometryJSON))

        #expect(dto.waypoints.map(\.lon) == [6.12, 6.12, 6.12])
        let keys = try encodedKeys(dto)
        #expect(keys.top == ["waypoints", "legs"])
        #expect(keys.legs == [["mode", "polyline6"], ["mode"]])
    }

    @Test func itineraryRequestsRejectAPayloadMissingARequiredField() {
        let noName = json(#""id": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "sportTypeCode": "hike""#, geometryJSON)
        #expect(throws: DecodingError.self) { try decoder.decode(Components.Schemas.CreateItineraryRequestDto.self, from: noName) }
        let noSport = json(#""name": "Tour du lac""#, geometryJSON)
        #expect(throws: DecodingError.self) { try decoder.decode(Components.Schemas.UpdateItineraryRequestDto.self, from: noSport) }
        let noLegs = json(#""waypoints": [{ "lat": 45.9, "lon": 6.12 }]"#)
        #expect(throws: DecodingError.self) {
            try decoder.decode(Components.Schemas.ItineraryMetricsPreviewRequestDto.self, from: noLegs)
        }
    }

    /// `GET /v1/itineraries/:id`, also the answer of a save (`itinerarySchema`).
    private let itineraryJSON = """
      "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "name": "Tour du lac", "sportTypeCode": "hike",
      "distanceM": 2224.4, "elevationGainM": 87.5, "elevationSource": "open_meteo",
      "waypoints": [{ "lat": 45.9, "lon": 6.12 }, { "lat": 45.92, "lon": 6.12 }],
      "legs": [{ "mode": "straight", "polyline6": "_mopvA_cptJ_pR?" }],
      "track": { "polyline6": "_mopvA_cptJ_pR?", "altitudesM": [446.5, 534] },
      "createdAt": "2026-10-10T07:00:00.500Z"
    """

    @Test func itineraryDetailDecodesAnAPIPayload() throws {
        let payload = json(itineraryJSON, #""updatedAt": "2026-10-10T08:00:00.500Z""#)

        let dto = try APIClient.decoder.decode(Components.Schemas.ItineraryDto_Output.self, from: payload)

        #expect(dto.id == "7c9e6679-7425-40de-944b-e07fc1f90ae7")
        #expect(dto.elevationSource == .open_meteo)
        #expect(dto.legs.map(\.mode) == [.straight])
        #expect(dto.track.altitudesM == [446.5, 534])
        #expect(dto.updatedAt.timeIntervalSince(dto.createdAt) == 3600)
    }

    @Test func itineraryDetailRejectsAPayloadMissingARequiredField() {
        #expect(throws: DecodingError.self) {
            try APIClient.decoder.decode(Components.Schemas.ItineraryDto_Output.self, from: json(itineraryJSON))
        }
    }

    /// `GET /v1/itineraries` (`listItinerariesResponseSchema`).
    private let listItemJSON = """
      "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "name": "Tour du lac", "sportTypeCode": "hike",
      "distanceM": 2224.4, "elevationGainM": 87.5, "updatedAt": "2026-10-10T08:00:00.500Z"
    """

    @Test func itineraryListPageDecodesAnAPIPayload() throws {
        let payload = Data(#"{ "items": [{\#(listItemJSON), "mapPolyline": "_zcwG_ijd@"}], "nextCursor": "abc" }"#.utf8)

        let dto = try APIClient.decoder.decode(Components.Schemas.ListItinerariesResponseDto_Output.self, from: payload)

        let item = try #require(dto.items.first)
        #expect(item.name == "Tour du lac")
        #expect(item.mapPolyline == "_zcwG_ijd@")
        #expect(dto.nextCursor == "abc")
    }

    @Test func itineraryListPageRejectsAPayloadMissingARequiredField() {
        let noThumbnail = Data(#"{ "items": [{\#(listItemJSON)}], "nextCursor": null }"#.utf8)
        #expect(throws: DecodingError.self) {
            try APIClient.decoder.decode(Components.Schemas.ListItinerariesResponseDto_Output.self, from: noThumbnail)
        }
    }

    /// `POST /v1/itineraries/metrics-preview` (`itineraryMetricsSchema`).
    @Test func itineraryMetricsDecodeAnAPIPayloadAndRejectAMissingField() throws {
        let dto = try decoder.decode(
            Components.Schemas.ItineraryMetricsDto_Output.self,
            from: json(#""distanceM": 2224.4, "elevationGainM": 87.5, "elevationSource": "mixed""#)
        )
        #expect(dto.distanceM == 2224.4)
        #expect(dto.elevationSource == .mixed)

        #expect(throws: DecodingError.self) {
            try decoder.decode(
                Components.Schemas.ItineraryMetricsDto_Output.self,
                from: json(#""distanceM": 2224.4, "elevationGainM": 87.5"#)
            )
        }
    }
}
