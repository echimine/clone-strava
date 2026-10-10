import Foundation
import GRDB

/// GRDB adapter of `ItineraryChangeQueue`, rows `rename_itinerary` and `delete_itinerary` of
/// `sync_operation` (ADR-008 §3, ADR-030 §8). Coalescing runs in one transaction, so at most
/// one change per Itinerary is ever pending.
struct GRDBItineraryChangeQueue: ItineraryChangeQueue {
    let database: AppDatabase

    func enqueue(_ change: ItineraryChange, for id: ItineraryID, at date: Date) async throws {
        try await database.writer.write { db in
            let pending = ItinerarySyncOperation.rows(of: id)
            if try pending.filter(SyncOperationRecord.Columns.type == ItinerarySyncOperation.delete.rawValue).fetchCount(db) > 0 {
                return
            }
            try pending.deleteAll(db)
            var record = SyncOperationRecord(
                type: ItinerarySyncOperation(change).rawValue,
                entityId: id.description,
                payload: try ItinerarySyncOperation.payload(of: change),
                nextAttemptAt: date,
                createdAt: date
            )
            try record.insert(db)
        }
    }

    func pending() async throws -> [PendingItineraryChange] {
        try await database.writer.read { db in
            try ItinerarySyncOperation.all
                .order(SyncOperationRecord.Columns.id)
                .fetchAll(db)
                .compactMap(PendingItineraryChange.init)
        }
    }

    func postpone(_ change: PendingItineraryChange, until date: Date, error: String) async throws {
        try await database.writer.write { db in
            guard var record = try SyncOperationRecord.fetchOne(db, key: change.id) else { return }
            record.attempts += 1
            record.nextAttemptAt = date
            record.lastError = error
            try record.update(db)
        }
    }

    func remove(_ change: PendingItineraryChange) async throws {
        try await database.writer.write { db in
            _ = try SyncOperationRecord.deleteOne(db, key: change.id)
        }
    }

    func clear() async throws {
        try await database.writer.write { db in
            _ = try ItinerarySyncOperation.all.deleteAll(db)
        }
    }
}

/// The Itinerary operation types of `sync_operation`, shared with `GRDBItineraryCache`, which
/// shows the local value of a pending change.
enum ItinerarySyncOperation: String, CaseIterable {
    case rename = "rename_itinerary"
    case delete = "delete_itinerary"

    init(_ change: ItineraryChange) {
        switch change {
        case .rename: self = .rename
        case .delete: self = .delete
        }
    }

    private struct RenamePayload: Codable {
        let name: String
    }

    static var all: QueryInterfaceRequest<SyncOperationRecord> {
        SyncOperationRecord.filter(allCases.map(\.rawValue).contains(SyncOperationRecord.Columns.type))
    }

    static func rows(of id: ItineraryID) -> QueryInterfaceRequest<SyncOperationRecord> {
        all.filter(SyncOperationRecord.Columns.entityID == id.description)
    }

    /// Ids of the Itineraries pending deletion, for `NOT IN` filters.
    static var pendingDeletionIDs: SQLRequest<String> {
        SQLRequest(sql: "SELECT entity_id FROM sync_operation WHERE type = ?", arguments: [delete.rawValue])
    }

    /// Ids of the Itineraries some change targets: a resync must not delete their rows.
    static var targetedIDs: SQLRequest<String> {
        SQLRequest(sql: "SELECT entity_id FROM sync_operation WHERE type IN (?, ?)", arguments: [rename.rawValue, delete.rawValue])
    }

    /// The name of each Itinerary with a pending rename, keyed by id.
    static func pendingNames(_ db: Database) throws -> [String: String] {
        let records = try all
            .filter(SyncOperationRecord.Columns.type == rename.rawValue)
            .order(SyncOperationRecord.Columns.id)
            .fetchAll(db)
        var names: [String: String] = [:]
        for record in records {
            names[record.entityId] = record.change.flatMap { change in
                if case .rename(let name) = change { name } else { nil }
            }
        }
        return names
    }

    static func payload(of change: ItineraryChange) throws -> String? {
        switch change {
        case .rename(let name): String(decoding: try JSONEncoder().encode(RenamePayload(name: name)), as: UTF8.self)
        case .delete: nil
        }
    }

    fileprivate static func change(type: String, payload: String?) -> ItineraryChange? {
        switch ItinerarySyncOperation(rawValue: type) {
        case .rename:
            guard let payload, let decoded = try? JSONDecoder().decode(RenamePayload.self, from: Data(payload.utf8)) else {
                return nil
            }
            return .rename(name: decoded.name)
        case .delete: return .delete
        case nil: return nil
        }
    }
}

private extension SyncOperationRecord {
    var change: ItineraryChange? {
        ItinerarySyncOperation.change(type: type, payload: payload)
    }
}

private extension PendingItineraryChange {
    init?(_ record: SyncOperationRecord) {
        guard let id = record.id, let itineraryID = ItineraryID(record.entityId), let change = record.change else {
            return nil
        }
        self.init(id: id, itineraryID: itineraryID, change: change, attempts: record.attempts, nextAttemptAt: record.nextAttemptAt)
    }
}
