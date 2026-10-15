import Foundation
import Testing
@testable import StravaClone

/// The Itinerary chip of the pre-start screen and "Démarrer avec cet Itinéraire"
/// (ADR-031 §2), over a fake Itinerary cache.
@MainActor
struct RecordingStoreItineraryTests {
    private let provider = FakeLocationProvider()
    private let repository: GRDBRecordingRepository
    private let service: RecordingService
    private let track = SyntheticTrack.through([(0, 0), (400, 0)])
    private let cache: FakeItineraryCacheReader

    init() throws {
        repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        service = RecordingService(locationProvider: provider, repository: repository)
        cache = FakeItineraryCacheReader(
            listings: [
                CachedItineraryListing(id: .fixture(1), name: "Col", sport: .ride, distance: Distance(meters: 400), hasTrack: true),
                CachedItineraryListing(id: .fixture(2), name: "Sentier", sport: .hike, distance: Distance(meters: 8_000), hasTrack: false),
            ],
            tracks: [CachedItineraryTrack(id: .fixture(1), points: track, distance: Distance(meters: 400))]
        )
    }

    private func makeStore() -> RecordingStore {
        RecordingStore(
            service: service,
            preferences: InMemoryRecordingPreferences(),
            itineraries: cache,
            ensureFullAccuracy: { true }
        )
    }

    @Test func listsTheCachedItinerariesWithNoneChosen() async {
        let store = makeStore()

        await store.loadItineraries()

        #expect(store.itineraries.map(\.name) == ["Col", "Sentier"])
        #expect(store.chosenItinerary == nil)
    }

    @Test func choosingAnItineraryAlignsTheSportWhichCanBeChangedBack() async {
        let store = makeStore()
        await store.loadItineraries()

        store.choose(store.itineraries[0])
        #expect(store.chosenItinerary?.id == .fixture(1))
        #expect(store.sport == .ride)

        store.sport = .run
        #expect(store.chosenItinerary?.id == .fixture(1))
    }

    @Test func anItineraryWithoutItsTrackOnThePhoneCannotBeChosen() async {
        let store = makeStore()
        await store.loadItineraries()

        store.choose(store.itineraries[1])

        #expect(store.chosenItinerary == nil)
        #expect(store.sport == .run)
    }

    @Test func startsFollowingTheChosenItinerary() async throws {
        let store = makeStore()
        await store.loadItineraries()
        store.choose(store.itineraries[0])

        await store.start()

        #expect(store.snapshot?.itinerary?.id == .fixture(1))
        #expect(try await repository.load()?.itinerary?.name == "Col")
    }

    @Test func anItineraryDeletedElsewhereBeforeStartResetsTheChipWithAToast() async throws {
        let store = makeStore()
        await store.loadItineraries()
        store.choose(store.itineraries[0])
        cache.delete(.fixture(1))

        await store.start()

        #expect(store.chosenItinerary == nil)
        #expect(store.toast == RecordingMessages.itineraryDeleted)
        #expect(try await repository.load() == nil)
    }

    @Test func aDeletionSeenWhenTheListReloadsAlsoResetsTheChip() async {
        let store = makeStore()
        await store.loadItineraries()
        store.choose(store.itineraries[0])
        cache.delete(.fixture(1))

        await store.loadItineraries()

        #expect(store.chosenItinerary == nil)
        #expect(store.toast == RecordingMessages.itineraryDeleted)
    }

    @Test func startWithThisItineraryOpensThePreStartScreenWithItChosen() async throws {
        let store = makeStore()

        await store.prepare(itineraryID: .fixture(1))

        #expect(store.chosenItinerary?.id == .fixture(1))
        #expect(store.sport == .ride)
        #expect(try await repository.load() == nil) // never starts by itself
    }

    @Test func theItineraryCanBeRemovedDuringTheRecording() async throws {
        let store = makeStore()
        await store.loadItineraries()
        store.choose(store.itineraries[0])
        await store.start()

        await store.removeItinerary()

        #expect(store.snapshot?.itinerary == nil)
        #expect(try await repository.load()?.itinerary == nil)
    }
}
