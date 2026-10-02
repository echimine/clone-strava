import Foundation

/// Sends a staged file (ADR-028 §3): create the import, `PUT` the file to the bucket,
/// then `complete`. Every step is replayable with the same `id`: on a retry after a
/// network drop, an import already past `pending` is simply returned.
struct ImportActivityFile: Sendable {
    let repository: ActivityImportRepository

    func callAsFunction(id: UUID, file: ImportFile, options: ImportOptions) async throws(ImportError) -> ActivityImport {
        let (created, upload) = try await repository.create(id: id, file: file, options: options)
        guard created.status == .pending else {
            return created
        }

        let target: UploadTarget
        if let upload {
            target = upload
        } else {
            target = try await repository.renewUploadURL(id: id)
        }
        do {
            try await repository.upload(file: file, to: target)
        } catch .uploadURLExpired {
            // The URL lives 15 min (ADR-019 §2): renew it once and retry.
            try await repository.upload(file: file, to: try await repository.renewUploadURL(id: id))
        }
        return try await repository.complete(id: id)
    }
}
