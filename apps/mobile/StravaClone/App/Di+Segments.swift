import SwiftUI

/// Segments (ADR-039 §15): the Map tab's Segments mode, creating a Segment, Plus › « Segments »,
/// a Segment's sheet and Leaderboard, and the Paywall their locks open in a sheet. The Segment is
/// drawn with the Itinerary editor: built here, the composition root, since features never build
/// each other's screens (ADR-007 rule 5).
extension Di {
    func makeSegmentCreationFlow() -> SegmentCreationFlow {
        let connectivityMonitor = connectivityMonitor
        return SegmentCreationFlow(isOnline: { connectivityMonitor.status.isConnected })
    }

    /// The Itinerary editor for the sport, without its stats card nor its journey events: the
    /// Segment's card reads the path it draws.
    func makeSegmentDrawingCanvas(sport: SegmentSport, onClose: @escaping () -> Void) -> SegmentDrawingCanvas {
        let editor = ItineraryEditor(
            sport: ItinerarySport(rawValue: sport.rawValue) ?? .run,
            router: itineraryRouter,
            metricsPreviewer: nil
        )
        let store = ItineraryEditorStore(editor: editor, connectivityChanges: connectivityChanges, tracking: .none)
        return SegmentDrawingCanvas(
            view: AnyView(ItineraryEditorView(store: store, onClose: onClose, showsStatsCard: false)),
            drawing: {
                let path: SegmentDrawing.Path = if let settled = editor.settledPath {
                    .settled(settled)
                } else {
                    editor.hasStartAndFinish ? .changing : .empty
                }
                return SegmentDrawing(path: path, distance: editor.displayedDraft.distance)
            }
        )
    }

    func makeSegmentDrawingStore(sport: SegmentSport) -> SegmentDrawingStore {
        let connectivityMonitor = connectivityMonitor
        return SegmentDrawingStore(
            sport: sport,
            preview: PreviewSegment(repository: APISegmentCreationRepository(apiClient: apiClient)),
            isOnline: { connectivityMonitor.status.isConnected }
        )
    }

    func makeSegmentCreateStore(candidate: SegmentCandidate) -> SegmentCreateStore {
        let connectivityMonitor = connectivityMonitor
        return SegmentCreateStore(
            candidate: candidate,
            create: CreateSegment(repository: APISegmentCreationRepository(apiClient: apiClient)),
            isOnline: { connectivityMonitor.status.isConnected }
        )
    }

    /// A new one each time Plus pushes the list.
    func makeFavoriteSegmentsStore() -> FavoriteSegmentsStore {
        FavoriteSegmentsStore(loadPage: LoadFavoriteSegments(repository: APIFavoriteSegmentsRepository(apiClient: apiClient)))
    }

    /// One for the Map tab, kept across mode switches.
    func makeSegmentMapStore() -> SegmentMapStore {
        SegmentMapStore(
            searchSegments: SearchMapSegments(repository: APISegmentMapRepository(apiClient: apiClient)),
            setFavorite: SetSegmentFavorite(repository: APISegmentRepository(apiClient: apiClient)),
            analytics: analytics
        )
    }

    /// A Segment's sheet, pushed in any stack; `onDeleted` pops it.
    func makeSegmentSheetStore(id: String, onDeleted: @escaping @MainActor () -> Void) -> SegmentSheetStore {
        let repository = APISegmentRepository(apiClient: apiClient)
        return SegmentSheetStore(
            segmentID: id,
            loadSheet: LoadSegmentSheet(repository: repository),
            setFavorite: SetSegmentFavorite(repository: repository),
            rename: RenameSegment(repository: repository),
            delete: DeleteSegment(repository: repository),
            analytics: analytics,
            onDeleted: onDeleted
        )
    }

    func makeLeaderboardStore(id: String) -> LeaderboardStore {
        LeaderboardStore(
            segmentID: id,
            loadLeaderboard: LoadLeaderboard(repository: APISegmentRepository(apiClient: apiClient)),
            analytics: analytics
        )
    }

    /// The Paywall a lock opens in a sheet. No notification primer on this path: `finish` only
    /// closes the sheet (ADR-039 §9).
    func makeSegmentPaywallStore(entry: AnalyticsEvent.PaywallEntry, finish: @escaping @MainActor () -> Void) -> PaywallStore {
        PaywallStore(service: subscriptionService, analytics: analytics, entry: entry, finish: finish)
    }
}
