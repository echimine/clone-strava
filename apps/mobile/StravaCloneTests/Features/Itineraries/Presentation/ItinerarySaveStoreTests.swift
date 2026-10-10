import Foundation
import Testing
@testable import StravaClone

/// "Enregistrer" in the editor (ADR-030 §6): name, save, and retry under the same id.
@MainActor
struct ItinerarySaveStoreTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)

    private func trace(_ points: [Coordinate]) async -> ItineraryDraft {
        let editor = ItineraryEditor(sport: .run, router: FakeItineraryRouter())
        for point in points {
            editor.addWaypoint(at: point)
        }
        await editor.settle()
        return editor.draft
    }

    private func makeStore(_ repository: FakeItineraryRepository) throws -> ItinerarySaveStore {
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        return ItinerarySaveStore(save: SaveItinerary(repository: repository, cache: cache), id: .fixture(4))
    }

    @Test func saveIsOfferedOnceThereIsAStartAndAFinish() async throws {
        let store = try makeStore(FakeItineraryRepository())

        #expect(store.blocker(for: await trace([a])) == "Placez un départ et une arrivée pour enregistrer.")
        #expect(store.blocker(for: await trace([a, b])) == nil)
    }

    @Test func theNameMustHaveOneToAHundredCharacters() throws {
        let store = try makeStore(FakeItineraryRepository())

        store.name = "   "
        #expect(!store.isNameValid)
        store.name = String(repeating: "a", count: 101)
        #expect(!store.isNameValid)
        store.name = "Tour du lac"
        #expect(store.isNameValid)
    }

    @Test func aSuccessfulSaveSendsTheEditorsIdAndEnds() async throws {
        let repository = FakeItineraryRepository()
        repository.createResults = [.success(.fixture(4))]
        let store = try makeStore(repository)
        store.name = "Tour du lac"

        await store.save(await trace([a, b]))

        #expect(store.phase == .saved)
        #expect(repository.creations.map(\.id) == [.fixture(4)])
        #expect(repository.creations.map(\.name) == ["Tour du lac"])
    }

    /// A `503` keeps the editor as it is and offers a retry, which replays the same id.
    @Test func aFailedSaveOffersARetryUnderTheSameId() async throws {
        let repository = FakeItineraryRepository()
        repository.createResults = [.failure(.unavailable), .success(.fixture(4))]
        let store = try makeStore(repository)
        store.name = "Tour du lac"
        let draft = await trace([a, b])

        await store.save(draft)
        #expect(store.phase == .failed(
            message: "Altitudes momentanément indisponibles : votre Itinéraire n'est pas encore enregistré.",
            canRetry: true
        ))

        await store.save(draft)
        #expect(store.phase == .saved)
        #expect(repository.creations.map(\.id) == [.fixture(4), .fixture(4)])
    }

    @Test func aRefusedSaveCannotBeRetried() async throws {
        let repository = FakeItineraryRepository()
        repository.createResults = [.failure(.invalid(code: "validation_error"))]
        let store = try makeStore(repository)
        store.name = "Tour du lac"

        await store.save(await trace([a, b]))

        #expect(store.phase == .failed(message: "L'Itinéraire a été refusé par le serveur.", canRetry: false))
    }
}
