import Foundation
import Testing
@testable import StravaClone

/// "Enregistrer" in the editor (ADR-030 §6): name, save, and retry under the same id.
@MainActor
struct ItinerarySaveStoreTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.902, longitude: 6.122)

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

    /// Only "Enregistrer" waits for a pending Leg (ADR-030 §2), and says why.
    @Test func saveExplainsItWaitsForAPendingLeg() async throws {
        let store = try makeStore(FakeItineraryRepository())
        let router = FakeItineraryRouter()
        await router.fail(with: .temporary)
        let editor = ItineraryEditor(sport: .run, router: router)
        editor.addWaypoint(at: a)
        editor.addWaypoint(at: b)
        await editor.settle()

        #expect(store.blocker(for: editor.draft)
            == "Un tronçon est en attente : il sera recalculé au retour du réseau, puis vous pourrez enregistrer.")

        await router.answer(with: FakeItineraryRouter.gridPath)
        editor.retryPendingLegs()
        #expect(store.blocker(for: editor.draft) == "Calcul du tracé en cours : patientez avant d'enregistrer.")
        await editor.settle()
        #expect(store.blocker(for: editor.draft) == nil)
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
        repository.createResults = [.success(.new(.fixture(4)))]
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
        repository.createResults = [.failure(.unavailable), .success(.new(.fixture(4)))]
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

    /// The first `POST` was stored but its answer lost; the athlete edits, then retries: the
    /// replay answers the old content, so the current draft follows as a `PUT`.
    @Test func aReplayAfterTheDraftChangedSendsTheCurrentDraftAsAnUpdate() async throws {
        let repository = FakeItineraryRepository()
        repository.createResults = [.failure(.network), .success(.replay(.fixture(4, name: "Tour du lac")))]
        repository.updateResults = [.success(.fixture(4, name: "Tour du lac par le col"))]
        let store = try makeStore(repository)
        store.name = "Tour du lac"
        await store.save(await trace([a, b]))

        store.name = "Tour du lac par le col"
        let edited = await trace([a, b, c])
        await store.save(edited)

        #expect(store.phase == .saved)
        #expect(repository.creations.map(\.id) == [.fixture(4), .fixture(4)])
        let expected = try edited.creation(id: .fixture(4), name: "Tour du lac par le col")
        #expect(repository.updates == [expected])
    }

    @Test func aReplayOfTheUnchangedDraftSendsNoUpdate() async throws {
        let repository = FakeItineraryRepository()
        repository.createResults = [.failure(.network), .success(.replay(.fixture(4)))]
        let store = try makeStore(repository)
        store.name = "Tour du lac"
        let draft = await trace([a, b])

        await store.save(draft)
        await store.save(draft)

        #expect(store.phase == .saved)
        #expect(repository.updates.isEmpty)
    }

    /// Once a replay shows the Itinerary exists, a failed update says the changes are not
    /// saved, and the retry replaces it (`PUT`) rather than posting again.
    @Test func aFailedUpdateAfterAReplayIsRetriedAsAnUpdate() async throws {
        let repository = FakeItineraryRepository()
        repository.createResults = [.failure(.network), .success(.replay(.fixture(4)))]
        repository.updateResults = [.failure(.unavailable), .success(.fixture(4))]
        let store = try makeStore(repository)
        store.name = "Tour du lac"
        await store.save(await trace([a, b]))
        let edited = await trace([a, b, c])

        await store.save(edited)
        #expect(store.phase == .failed(
            message: "Altitudes momentanément indisponibles : vos modifications ne sont pas encore enregistrées.",
            canRetry: true
        ))

        await store.save(edited)
        #expect(store.phase == .saved)
        #expect(repository.creations.count == 2)
        #expect(repository.updates.count == 2)
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
