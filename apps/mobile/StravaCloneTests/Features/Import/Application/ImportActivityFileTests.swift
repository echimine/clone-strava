import Foundation
import Testing
@testable import StravaClone

struct ImportActivityFileTests {
    private let target = UploadTarget(url: URL(string: "https://bucket.test/first")!, expiresAt: .now)

    @Test func createsUploadsThenCompletes() async throws {
        let repository = FakeActivityImportRepository()
        repository.createResult = .success((.fixture(status: .pending), target))

        let result = try await ImportActivityFile(repository: repository)(id: UUID(), file: .fixture, options: ImportOptions())

        #expect(repository.calls == ["create", "upload", "complete"])
        #expect(repository.uploadedTo == [target.url])
        #expect(result.status == .processing)
    }

    @Test func renewsAnExpiredUploadURLOnce() async throws {
        let repository = FakeActivityImportRepository()
        repository.createResult = .success((.fixture(status: .pending), target))
        repository.uploadResults = [.failure(.uploadURLExpired), .success(())]

        _ = try await ImportActivityFile(repository: repository)(id: UUID(), file: .fixture, options: ImportOptions())

        #expect(repository.calls == ["create", "upload", "renewUploadURL", "upload", "complete"])
        #expect(repository.uploadedTo.last == URL(string: "https://bucket.test/renewed"))
    }

    @Test func aReplayedImportAlreadyPastPendingIsReturnedAsIs() async throws {
        let repository = FakeActivityImportRepository()
        repository.createResult = .success((.fixture(status: .imported), nil))

        let result = try await ImportActivityFile(repository: repository)(id: UUID(), file: .fixture, options: ImportOptions())

        #expect(repository.calls == ["create"])
        #expect(result.status == .imported)
    }

    @Test func propagatesCreateFailures() async {
        let repository = FakeActivityImportRepository()
        repository.createResult = .failure(.rateLimited)

        await #expect(throws: ImportError.rateLimited) {
            try await ImportActivityFile(repository: repository)(id: UUID(), file: .fixture, options: ImportOptions())
        }
    }
}

struct PrepareImportFileTests {
    @Test func rejectsUnsupportedExtensions() {
        #expect(throws: ImportError.unsupportedFile) {
            try PrepareImportFile(staging: FakeImportFileStaging())(URL(fileURLWithPath: "/tmp/route.kml"))
        }
    }

    @Test func rejectsFilesAbove25MB() {
        #expect(throws: ImportError.fileTooLarge) {
            try PrepareImportFile(staging: FakeImportFileStaging(sizeBytes: 26 * 1024 * 1024))(URL(fileURLWithPath: "/tmp/ride.fit"))
        }
    }

    @Test func detectsTheFormatFromTheExtension() throws {
        let file = try PrepareImportFile(staging: FakeImportFileStaging())(URL(fileURLWithPath: "/tmp/Morning.TCX"))
        #expect(file.format == .tcx)
    }
}
