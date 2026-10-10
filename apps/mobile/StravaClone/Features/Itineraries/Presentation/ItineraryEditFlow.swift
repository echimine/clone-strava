import Foundation
import Observation

/// "Modifier" on an Itinerary's detail (ADR-030 §5, §8). The editor only works online, so
/// offline the button stays active and shows "Connexion requise". Online, the Waypoints and
/// Legs are loaded (`GET /:id`) and the editor reopens on them as stored, with no routing.
@Observable
@MainActor
final class ItineraryEditFlow {
    /// The editor open on the Itinerary, with its save on the same id.
    struct Session: Identifiable {
        let id: ItineraryID
        let editorStore: ItineraryEditorStore
        let saveStore: ItinerarySaveStore
    }

    let id: ItineraryID
    /// Shown full screen while set.
    var session: Session?
    var toast: String?
    /// The Waypoints and Legs are on their way: the button waits.
    private(set) var isLoading = false

    @ObservationIgnored private let isOnline: @MainActor () -> Bool
    @ObservationIgnored private let load: LoadSavedItinerary
    @ObservationIgnored private let makeEditorStore: @MainActor (ItineraryDraft) -> ItineraryEditorStore
    @ObservationIgnored private let makeSaveStore: @MainActor (SavedItinerary) -> ItinerarySaveStore
    @ObservationIgnored private let analytics: any AnalyticsClient

    init(
        id: ItineraryID,
        isOnline: @escaping @MainActor () -> Bool,
        load: LoadSavedItinerary,
        makeEditorStore: @escaping @MainActor (ItineraryDraft) -> ItineraryEditorStore,
        makeSaveStore: @escaping @MainActor (SavedItinerary) -> ItinerarySaveStore,
        analytics: any AnalyticsClient = NoAnalyticsClient()
    ) {
        self.id = id
        self.isOnline = isOnline
        self.load = load
        self.makeEditorStore = makeEditorStore
        self.makeSaveStore = makeSaveStore
        self.analytics = analytics
    }

    func start() async {
        guard !isLoading, session == nil else { return }
        guard isOnline() else {
            toast = ItineraryMessages.connectionRequired
            analytics.capture(.itineraryOfflineEditBlocked(action: .edit))
            return
        }
        isLoading = true
        defer { isLoading = false }
        let saved: SavedItinerary
        do {
            saved = try await load(id: id)
        } catch {
            toast = ItineraryMessages.editUnavailable(error)
            return
        }
        guard let draft = ItineraryDraft(restoring: saved) else {
            toast = ItineraryMessages.editUnavailable(.server(code: nil))
            return
        }
        session = Session(id: id, editorStore: makeEditorStore(draft), saveStore: makeSaveStore(saved))
    }

    /// The editor closes, saved or not.
    func close() {
        session = nil
    }
}
