import Foundation
import GRDB

/// The followed Itinerary columns of the `recording` row (migration `recording_itinerary_v1`,
/// ADR-031 §10), written apart from the rest of the row: the progress changes at each fix,
/// the track only at Start and on removal.
extension GRDBRecordingRepository {
    func saveItinerary(_ itinerary: FollowedItinerary?, of id: ActivityID) async throws {
        try await database.writer.write { db in
            let saved = itinerary?.progress.saved
            try db.execute(
                sql: """
                UPDATE recording SET itinerary_id = ?, itinerary_name = ?, itinerary_track_polyline6 = ?,
                    itinerary_distance_m = ?, itinerary_progress_m = ?, itinerary_snapped = ?
                WHERE activity_id = ?
                """,
                arguments: [
                    itinerary?.id.description,
                    itinerary?.name,
                    itinerary.map { EncodedPolyline(encoding: $0.track, precision: 6).value },
                    itinerary?.progress.total.meters,
                    saved?.alongM,
                    saved?.hasSnapped,
                    id.description,
                ]
            )
        }
    }

    func saveItineraryProgress(_ progress: ItineraryProgress.Saved, of id: ActivityID) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE recording SET itinerary_progress_m = ?, itinerary_snapped = ?
                WHERE activity_id = ? AND itinerary_id IS NOT NULL
                """,
                arguments: [progress.alongM, progress.hasSnapped, id.description]
            )
        }
    }

    /// The followed Itinerary of the stored Recording, if any.
    static func fetchItinerary(_ db: Database) throws -> FollowedItinerary? {
        guard let row = try FollowedItineraryRow.fetchOne(db),
              let rawID = row.itineraryId, let id = ItineraryID(rawID),
              let polyline = row.itineraryTrackPolyline6,
              let distance = row.itineraryDistanceM
        else { return nil }
        return FollowedItinerary(
            id: id,
            name: row.itineraryName ?? "",
            track: EncodedPolyline(value: polyline, precision: 6).decode(),
            total: Distance(meters: distance),
            saved: ItineraryProgress.Saved(alongM: row.itineraryProgressM ?? 0, hasSnapped: row.itinerarySnapped ?? false)
        )
    }
}

private struct FollowedItineraryRow: Decodable, FetchableRecord, TableRecord {
    static let databaseTableName = "recording"
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseSelection: [any SQLSelectable] {
        [
            Column("itinerary_id"), Column("itinerary_name"), Column("itinerary_track_polyline6"),
            Column("itinerary_distance_m"), Column("itinerary_progress_m"), Column("itinerary_snapped"),
        ]
    }

    var itineraryId: String?
    var itineraryName: String?
    var itineraryTrackPolyline6: String?
    var itineraryDistanceM: Double?
    var itineraryProgressM: Double?
    var itinerarySnapped: Bool?
}
