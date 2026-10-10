import Foundation
import Observation

/// State of the Map tab sheet (spec #22, ADR-030 §8): the Itineraries from the same cache
/// as Mes Itinéraires, resynced each time the sheet opens.
@Observable
@MainActor
final class MapItinerariesStore {
    let list: ItineraryListStore

    @ObservationIgnored private let makeDetailStore: @MainActor (ItineraryID) -> ItineraryDetailStore

    init(list: ItineraryListStore, makeDetailStore: @escaping @MainActor (ItineraryID) -> ItineraryDetailStore) {
        self.list = list
        self.makeDetailStore = makeDetailStore
    }

    /// ADR-030 §8: opening the sheet is a resync trigger. Once refreshed, the list counts as viewed.
    func sheetOpened() async {
        await list.refresh()
        await list.viewed()
    }

    /// Detail of the touched Itinerary, until it is closed or leaves the cache (deleted
    /// elsewhere, `404`): the sheet then shows the list again.
    var detail: ItineraryDetailStore? {
        selection?.isGone == true ? nil : selection
    }

    private var selection: ItineraryDetailStore?
    @ObservationIgnored private var selected: ItinerarySummary?

    /// A touch on a card: the map frames the Itinerary and the sheet shows its detail.
    func select(_ itinerary: ItinerarySummary) {
        selected = itinerary
        selection = makeDetailStore(itinerary.id)
    }

    func closeDetail() {
        selection = nil
        selected = nil
    }

    /// Path the map frames: the full track once its detail is cached, otherwise the card's
    /// simplified path, which is always cached (offline too).
    var focusedPath: [Coordinate]? {
        guard let detail, let selected else { return nil }
        return (detail.detail?.track.polyline ?? selected.mapPolyline).decode()
    }
}
