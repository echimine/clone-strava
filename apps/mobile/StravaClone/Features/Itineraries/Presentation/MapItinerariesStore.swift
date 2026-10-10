import Foundation
import Observation

/// State of the Map tab carousel (spec #22, ADR-030 §8): the Itineraries from the same cache
/// as Mes Itinéraires, resynced each time the carousel shows. The tab opens on the athlete:
/// a card is focused, and framed on the map, once the athlete scrolls the carousel to it;
/// a touch pushes its detail.
@Observable
@MainActor
final class MapItinerariesStore {
    let list: ItineraryListStore
    /// Card the athlete scrolled the carousel to, none until then. It may outlive its
    /// Itinerary (deleted elsewhere): the map then frames nothing.
    var focusedID: ItineraryID?

    @ObservationIgnored let makeDetailStore: @MainActor (ItineraryID) -> ItineraryDetailStore
    @ObservationIgnored let makeEditFlow: @MainActor (ItineraryID) -> ItineraryEditFlow

    init(
        list: ItineraryListStore,
        makeDetailStore: @escaping @MainActor (ItineraryID) -> ItineraryDetailStore,
        makeEditFlow: @escaping @MainActor (ItineraryID) -> ItineraryEditFlow
    ) {
        self.list = list
        self.makeDetailStore = makeDetailStore
        self.makeEditFlow = makeEditFlow
    }

    /// ADR-030 §8: showing the carousel is a resync trigger. Once refreshed, the list counts as viewed.
    func appeared() async {
        await list.refresh()
        await list.viewed()
    }

    var focused: ItinerarySummary? {
        list.itineraries.first { $0.id == focusedID }
    }

    /// Path the map frames: the focused card's simplified path, always cached (offline too).
    var focusedPath: [Coordinate]? {
        focused?.mapPolyline.decode()
    }
}
