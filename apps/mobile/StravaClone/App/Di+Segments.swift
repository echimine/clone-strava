import SwiftUI

/// Creating a Segment and Plus › « Segments » (ADR-039 §15). The Segment is drawn with the
/// Itinerary editor: built here, the composition root, since features never build each other's
/// screens (ADR-007 rule 5).
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
            repository: APISegmentCreationRepository(apiClient: apiClient),
            isOnline: { connectivityMonitor.status.isConnected }
        )
    }

    func makeSegmentCreateStore(candidate: SegmentCandidate) -> SegmentCreateStore {
        let connectivityMonitor = connectivityMonitor
        return SegmentCreateStore(
            candidate: candidate,
            repository: APISegmentCreationRepository(apiClient: apiClient),
            isOnline: { connectivityMonitor.status.isConnected }
        )
    }

    /// A new one each time Plus pushes the list.
    func makeStarredSegmentsStore() -> StarredSegmentsStore {
        StarredSegmentsStore(repository: APIStarredSegmentsRepository(apiClient: apiClient))
    }
}
