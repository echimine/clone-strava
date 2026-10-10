import Foundation
import GRDB

/// GRDB adapter of `ItineraryCache` (ADR-030 §8), tables `itinerary` and `itinerary_detail`
/// (migration `itineraries_v1` in `AppDatabase`). Rows follow the API: one per Itinerary,
/// its detail deleted with it.
struct GRDBItineraryCache: ItineraryCache {
    let database: AppDatabase

    func observeSummaries(limit: Int) -> AsyncStream<[ItinerarySummary]> {
        let observation = ValueObservation
            .tracking { db in try Self.fetchSummaries(db, limit: limit) }
            .removeDuplicates()
        let writer = database.writer
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await summaries in observation.values(in: writer) {
                        continuation.yield(summaries)
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func summaries(limit: Int) async throws -> [ItinerarySummary] {
        try await database.writer.read { db in try Self.fetchSummaries(db, limit: limit) }
    }

    func detail(id: ItineraryID) async throws -> ItineraryDetail? {
        try await database.writer.read { db in
            guard
                let row = try ItineraryRow.fetchOne(db, key: id.description),
                let detail = try ItineraryDetailRow.fetchOne(db, key: id.description)
            else { return nil }
            return detail.model(row: row)
        }
    }

    func save(_ detail: ItineraryDetail, mapPolyline: EncodedPolyline) async throws {
        try await database.writer.write { db in
            try ItineraryRow(detail: detail, mapPolyline: mapPolyline).upsert(db)
            try ItineraryDetailRow(detail).upsert(db)
        }
    }

    func replaceSummaries(with summaries: [ItinerarySummary]) async throws {
        try await database.writer.write { db in
            let ids = summaries.map(\.id.description)
            // #38: keep the rows a pending sync operation targets.
            try ItineraryRow.filter(!ids.contains(Column("id"))).deleteAll(db)
            for summary in summaries {
                try ItineraryRow(summary).upsert(db)
            }
        }
    }

    func clear() async throws {
        try await database.writer.write { db in
            _ = try ItineraryDetailRow.deleteAll(db)
            _ = try ItineraryRow.deleteAll(db)
        }
    }

    private static func fetchSummaries(_ db: Database, limit: Int) throws -> [ItinerarySummary] {
        try ItineraryRow
            .order(Column("updated_at").desc, Column("id"))
            .limit(limit)
            .fetchAll(db)
            .compactMap(\.summary)
    }
}

// MARK: Records

/// Shared column conventions: snake_case like the API's database; dates as seconds since
/// 2001, `Date`'s own storage, so they round-trip exactly.
private protocol ItineraryRecord: Codable, FetchableRecord, PersistableRecord {}

extension ItineraryRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseDateDecodingStrategy: DatabaseDateDecodingStrategy { .timeIntervalSinceReferenceDate }
    static var databaseDateEncodingStrategy: DatabaseDateEncodingStrategy { .timeIntervalSinceReferenceDate }
}

private struct ItineraryRow: ItineraryRecord {
    static let databaseTableName = "itinerary"

    var id: String
    var name: String
    var sportTypeCode: String
    var distanceM: Double
    var elevationGainM: Double
    var mapPolyline: String
    var updatedAt: Date

    init(_ summary: ItinerarySummary) {
        id = summary.id.description
        name = summary.name
        sportTypeCode = summary.sport.code
        distanceM = summary.distance.meters
        elevationGainM = summary.elevationGain
        mapPolyline = summary.mapPolyline.value
        updatedAt = summary.updatedAt
    }

    init(detail: ItineraryDetail, mapPolyline: EncodedPolyline) {
        self.init(ItinerarySummary(
            id: detail.id,
            name: detail.name,
            sport: detail.sport,
            distance: detail.distance,
            elevationGain: detail.elevationGain,
            mapPolyline: mapPolyline,
            updatedAt: detail.updatedAt
        ))
    }

    var summary: ItinerarySummary? {
        guard let id = ItineraryID(id) else { return nil }
        return ItinerarySummary(
            id: id,
            name: name,
            sport: SportType(code: sportTypeCode),
            distance: Distance(meters: distanceM),
            elevationGain: elevationGainM,
            mapPolyline: EncodedPolyline(value: mapPolyline),
            updatedAt: updatedAt
        )
    }
}

private struct ItineraryDetailRow: ItineraryRecord {
    static let databaseTableName = "itinerary_detail"

    var itineraryId: String
    var elevationSource: String
    var trackPolyline6: String
    var trackAltitudesM: [Double]
    var createdAt: Date
    var updatedAt: Date

    init(_ detail: ItineraryDetail) {
        itineraryId = detail.id.description
        elevationSource = detail.elevationSource.rawValue
        trackPolyline6 = detail.track.polyline.value
        trackAltitudesM = detail.track.altitudes
        createdAt = detail.createdAt
        updatedAt = detail.updatedAt
    }

    /// Name, sport and figures come from the row, which a resync keeps current.
    func model(row: ItineraryRow) -> ItineraryDetail? {
        guard let id = ItineraryID(itineraryId), let source = ElevationSource(rawValue: elevationSource) else {
            return nil
        }
        return ItineraryDetail(
            id: id,
            name: row.name,
            sport: SportType(code: row.sportTypeCode),
            distance: Distance(meters: row.distanceM),
            elevationGain: row.elevationGainM,
            elevationSource: source,
            track: ItineraryTrack(polyline: EncodedPolyline(value: trackPolyline6, precision: 6), altitudes: trackAltitudesM),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
