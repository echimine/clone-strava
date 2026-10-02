import Foundation
import Testing
@testable import StravaClone

@MainActor
struct ImportStoreTests {
    private func makeStore(_ repository: FakeActivityImportRepository) -> ImportStore {
        ImportStore(
            prepareFile: PrepareImportFile(staging: FakeImportFileStaging()),
            importFile: ImportActivityFile(repository: repository),
            tracker: ImportTracker(
                repository: repository,
                events: FakeImportEventSource(),
                pollInterval: .milliseconds(10),
                timeout: .seconds(5)
            )
        )
    }

    private let target = UploadTarget(url: URL(string: "https://bucket.test/u")!, expiresAt: .now)

    @Test func pickingAFileOpensTheConfirmation() {
        let store = makeStore(FakeActivityImportRepository())
        store.startImport()
        #expect(store.isPickingFile)

        store.filePicked(.success(URL(fileURLWithPath: "/tmp/run.gpx")))

        #expect(store.confirmation?.file.fileName == "run.gpx")
        #expect(store.confirmation?.sportRequired == false)
    }

    @Test func anUnsupportedFileShowsAnError() {
        let store = makeStore(FakeActivityImportRepository())
        store.filePicked(.success(URL(fileURLWithPath: "/tmp/route.kml")))

        #expect(store.confirmation == nil)
        #expect(store.banner == .failed(message: "Choisissez un fichier .gpx, .tcx ou .fit.", canPickSport: false))
    }

    @Test func confirmingImportsAndShowsTheResult() async {
        let repository = FakeActivityImportRepository()
        repository.createResult = .success((.fixture(status: .pending), target))
        repository.fetchResults = [.fixture(status: .imported, activityId: "a1")]
        let store = makeStore(repository)
        store.filePicked(.success(URL(fileURLWithPath: "/tmp/run.gpx")))

        await store.confirm(ImportOptions(sport: .run))

        #expect(store.confirmation == nil)
        #expect(store.banner == .imported(fileName: "run.gpx"))
    }

    @Test func unknownSportOffersToPickTheSportForTheSameFile() async {
        let repository = FakeActivityImportRepository()
        repository.createResult = .success((.fixture(status: .pending), target))
        repository.fetchResults = [.fixture(status: .failed, errorCode: "unknown_sport")]
        let store = makeStore(repository)
        store.filePicked(.success(URL(fileURLWithPath: "/tmp/run.gpx")))

        await store.confirm(ImportOptions())

        guard case .failed(_, let canPickSport) = store.banner else {
            Issue.record("expected a failure banner, got \(String(describing: store.banner))")
            return
        }
        #expect(canPickSport)

        store.pickSportAgain()
        #expect(store.banner == nil)
        #expect(store.confirmation?.file.fileName == "run.gpx")
        #expect(store.confirmation?.sportRequired == true)
    }

    @Test func offlineIsReportedInFrench() async {
        let repository = FakeActivityImportRepository()
        repository.createResult = .failure(.offline)
        let store = makeStore(repository)
        store.filePicked(.success(URL(fileURLWithPath: "/tmp/run.gpx")))

        await store.confirm(ImportOptions())

        #expect(store.banner == .failed(message: "Pas de connexion internet.", canPickSport: false))
    }
}
