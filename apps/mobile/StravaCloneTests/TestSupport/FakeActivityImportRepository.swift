import Foundation
@testable import StravaClone

/// In-memory `ActivityImportRepository` (ADR-025 §3): scripted answers, recorded calls.
final class FakeActivityImportRepository: ActivityImportRepository, @unchecked Sendable {
    private let lock = NSLock()

    var createResult: Result<(ActivityImport, UploadTarget?), ImportError> = .failure(.network)
    /// Successive upload results; the last one repeats.
    var uploadResults: [Result<Void, ImportError>] = [.success(())]
    var completeStatus: ImportStatus = .processing
    /// Successive `fetch` answers; the last one repeats.
    var fetchResults: [ActivityImport] = []

    private(set) var calls: [String] = []
    private(set) var uploadedTo: [URL] = []
    private(set) var fetchCount = 0

    private func record(_ call: String) {
        lock.withLock { calls.append(call) }
    }

    func create(id: UUID, file: ImportFile, options: ImportOptions) async throws(ImportError)
        -> (import: ActivityImport, upload: UploadTarget?)
    {
        record("create")
        return try createResult.get()
    }

    func renewUploadURL(id: UUID) async throws(ImportError) -> UploadTarget {
        record("renewUploadURL")
        return UploadTarget(url: URL(string: "https://bucket.test/renewed")!, expiresAt: .now)
    }

    func upload(file: ImportFile, to target: UploadTarget) async throws(ImportError) {
        record("upload")
        let result: Result<Void, ImportError> = lock.withLock {
            uploadedTo.append(target.url)
            return uploadResults.count > 1 ? uploadResults.removeFirst() : uploadResults[0]
        }
        try result.get()
    }

    func complete(id: UUID) async throws(ImportError) -> ActivityImport {
        record("complete")
        return .fixture(id: id, status: completeStatus)
    }

    func fetch(id: UUID) async throws(ImportError) -> ActivityImport {
        lock.withLock {
            fetchCount += 1
            return fetchResults.count > 1 ? fetchResults.removeFirst() : (fetchResults.first ?? .fixture(id: id, status: .processing))
        }
    }
}

/// `ImportEventSource` driven by the test.
final class FakeImportEventSource: ImportEventSource, @unchecked Sendable {
    let stream: AsyncStream<ImportEvent>
    let continuation: AsyncStream<ImportEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream<ImportEvent>.makeStream()
    }

    func events() async -> AsyncStream<ImportEvent> {
        stream
    }
}

/// `ImportFileStaging` returning a fixed file.
struct FakeImportFileStaging: ImportFileStaging {
    var sizeBytes = 1_000

    func stage(_ pickedURL: URL) throws(ImportError) -> ImportFile {
        ImportFile(
            localURL: pickedURL,
            fileName: pickedURL.lastPathComponent,
            format: ImportFormat(fileName: pickedURL.lastPathComponent) ?? .gpx,
            sizeBytes: sizeBytes
        )
    }
}

extension ActivityImport {
    static func fixture(
        id: UUID = UUID(),
        status: ImportStatus,
        activityId: String? = nil,
        errorCode: String? = nil
    ) -> ActivityImport {
        ActivityImport(id: id, format: .gpx, fileName: "run.gpx", status: status, activityId: activityId, errorCode: errorCode)
    }
}

extension ImportFile {
    static let fixture = ImportFile(
        localURL: URL(fileURLWithPath: "/tmp/run.gpx"),
        fileName: "run.gpx",
        format: .gpx,
        sizeBytes: 1_000
    )
}
