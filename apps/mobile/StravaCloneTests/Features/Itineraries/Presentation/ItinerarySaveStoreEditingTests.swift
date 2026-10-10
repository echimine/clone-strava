import Foundation
import Testing
@testable import StravaClone

/// "Enregistrer" after "Modifier" (ADR-030 §6): the same Itinerary is replaced (`PUT`), never
/// copied; a `503` keeps the editor as it is and offers a retry.
@MainActor
struct ItinerarySaveStoreEditingTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)

    private var saved: SavedItinerary {
        SavedItinerary(id: .fixture(9), name: "Tour du lac", sport: .run, waypoints: [a, b], legs: [.straight])
    }

    private func makeStore(_ repository: FakeItineraryRepository) throws -> ItinerarySaveStore {
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        return ItinerarySaveStore(update: UpdateItinerary(repository: repository, cache: cache), itinerary: saved)
    }

    @Test func theNameStartsAsSaved() throws {
        let store = try makeStore(FakeItineraryRepository())

        #expect(store.id == .fixture(9))
        #expect(store.name == "Tour du lac")
    }

    @Test func savingReplacesTheSameItinerary() async throws {
        let repository = FakeItineraryRepository()
        repository.updateResults = [.success(.fixture(9))]
        let store = try makeStore(repository)
        store.name = "Tour du lac par le col"

        await store.save(try #require(ItineraryDraft(restoring: saved)))

        #expect(store.phase == .saved)
        #expect(repository.creations.isEmpty)
        #expect(repository.updates.map(\.id) == [.fixture(9)])
        #expect(repository.updates.map(\.name) == ["Tour du lac par le col"])
        #expect(repository.updates.map(\.legs) == [[.straight]])
    }

    @Test func aFailedSaveOffersARetryOnTheSameItinerary() async throws {
        let repository = FakeItineraryRepository()
        repository.updateResults = [.failure(.unavailable), .success(.fixture(9))]
        let store = try makeStore(repository)
        let draft = try #require(ItineraryDraft(restoring: saved))

        await store.save(draft)
        #expect(store.phase == .failed(
            message: "Altitudes momentanément indisponibles : vos modifications ne sont pas encore enregistrées.",
            canRetry: true
        ))

        await store.save(draft)
        #expect(store.phase == .saved)
        #expect(repository.updates.map(\.id) == [.fixture(9), .fixture(9)])
    }

    /// The Itinerary exists: a failed edit says the changes, not the Itinerary, are unsaved.
    @Test(arguments: [
        (ItineraryError.offline, "Vous êtes hors ligne : vos modifications ne sont pas encore enregistrées."),
        (.network, "Enregistrement impossible pour le moment : vos modifications ne sont pas encore enregistrées."),
        (.invalid(code: "validation_error"), "Vos modifications ont été refusées par le serveur."),
        (.notFound, "Cet Itinéraire n'existe plus."),
        (.unauthorized, "Votre session a expiré, reconnectez-vous."),
    ])
    func aFailedEditSaysTheChangesAreNotSaved(error: ItineraryError, message: String) async throws {
        let repository = FakeItineraryRepository()
        repository.updateResults = [.failure(error)]
        let store = try makeStore(repository)

        await store.save(try #require(ItineraryDraft(restoring: saved)))

        #expect(store.phase == .failed(message: message, canRetry: error.isRetryable))
    }
}
