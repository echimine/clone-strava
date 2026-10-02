import Foundation

/// Data access port of the import (ADR-007): `/v1/activity-imports` and the bucket.
protocol ActivityImportRepository: Sendable {
    /// `POST /v1/activity-imports`, idempotent on `id`. `upload` is present while `pending`.
    func create(id: UUID, file: ImportFile, options: ImportOptions) async throws(ImportError)
        -> (import: ActivityImport, upload: UploadTarget?)
    func renewUploadURL(id: UUID) async throws(ImportError) -> UploadTarget
    /// `PUT` of the file to the pre-signed URL; `.uploadURLExpired` on `403`.
    func upload(file: ImportFile, to target: UploadTarget) async throws(ImportError)
    func complete(id: UUID) async throws(ImportError) -> ActivityImport
    func fetch(id: UUID) async throws(ImportError) -> ActivityImport
}

/// Realtime notifications about the user's imports (ADR-028 §10).
enum ImportEvent: Equatable, Sendable {
    case completed(importId: UUID)
    case failed(importId: UUID)

    var importId: UUID {
        switch self {
        case .completed(let id), .failed(let id): id
        }
    }
}

protocol ImportEventSource: Sendable {
    func events() async -> AsyncStream<ImportEvent>
}

/// Copies a file picked in the Files app into the app's sandbox (security-scoped access).
protocol ImportFileStaging: Sendable {
    func stage(_ pickedURL: URL) throws(ImportError) -> ImportFile
}
