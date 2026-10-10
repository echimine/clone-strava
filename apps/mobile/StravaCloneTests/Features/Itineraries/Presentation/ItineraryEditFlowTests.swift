import Foundation
import Testing
@testable import StravaClone

/// "Modifier" from the detail (ADR-030 §8): online, the Waypoints and Legs are loaded and the
/// editor reopens on them without routing; offline, the button says "Connexion requise".
@MainActor
struct ItineraryEditFlowTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let corner = Coordinate(latitude: 45.900, longitude: 6.121)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)

    private var saved: SavedItinerary {
        SavedItinerary(
            id: .fixture(3),
            name: "Tour du lac",
            sport: .walk,
            waypoints: [a, b],
            legs: [.follow(EncodedPolyline(encoding: [a, corner, b], precision: 6))]
        )
    }

    private func makeFlow(
        _ repository: FakeItineraryRepository,
        router: FakeItineraryRouter = FakeItineraryRouter(),
        isOnline: Bool = true
    ) throws -> ItineraryEditFlow {
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        return ItineraryEditFlow(
            id: .fixture(3),
            isOnline: { isOnline },
            load: LoadSavedItinerary(repository: repository, cache: cache),
            makeEditorStore: { ItineraryEditorStore(editor: ItineraryEditor(restoring: $0, router: router)) },
            makeSaveStore: { ItinerarySaveStore(update: UpdateItinerary(repository: repository, cache: cache), itinerary: $0) }
        )
    }

    @Test func offlineModifierSaysAConnectionIsRequired() async throws {
        let repository = FakeItineraryRepository()
        let flow = try makeFlow(repository, isOnline: false)

        await flow.start()

        #expect(flow.toast == "Connexion requise")
        #expect(flow.session == nil)
        #expect(repository.savedItineraryCalls.isEmpty)
    }

    @Test func theEditorReopensOnTheStoredItineraryWithoutRouting() async throws {
        let repository = FakeItineraryRepository()
        repository.setSavedItinerary(.success(saved), for: .fixture(3))
        let router = FakeItineraryRouter()
        let flow = try makeFlow(repository, router: router)

        await flow.start()

        let session = try #require(flow.session)
        let draft = session.editorStore.editor.draft
        await session.editorStore.editor.settle()
        #expect(draft.sport == .walk)
        #expect(draft.waypoints.map(\.coordinate) == [a, b])
        #expect(draft.legs.map(\.mode) == [.follow])
        #expect(draft.legs.map(\.path) == [[a, corner, b]])
        #expect(await router.calls.isEmpty)
        #expect(session.saveStore.id == .fixture(3))
        #expect(session.saveStore.name == "Tour du lac")
        #expect(flow.toast == nil)
    }

    @Test func closingTheEditorEndsTheSession() async throws {
        let repository = FakeItineraryRepository()
        repository.setSavedItinerary(.success(saved), for: .fixture(3))
        let flow = try makeFlow(repository)
        await flow.start()

        flow.close()

        #expect(flow.session == nil)
    }

    @Test(arguments: [
        (ItineraryError.offline, "Connexion requise"),
        (.network, "Chargement de l'Itinéraire impossible pour le moment."),
        (.notFound, "Cet Itinéraire n'existe plus."),
    ])
    func aFailedLoadKeepsTheDetailAndSaysWhy(error: ItineraryError, message: String) async throws {
        let repository = FakeItineraryRepository()
        repository.setSavedItinerary(.failure(error), for: .fixture(3))
        let flow = try makeFlow(repository)

        await flow.start()

        #expect(flow.session == nil)
        #expect(flow.toast == message)
        #expect(!flow.isLoading)
    }
}
