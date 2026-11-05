import Observation
import SwiftUI

/// Where creating a Segment opens (ADR-039 §15): the Map's « Créer » menu, or the « + » of
/// Plus › « Segments ». Offline, the entry stays active and says « Connexion requise ».
@Observable
@MainActor
final class SegmentCreationFlow {
    enum Entry: Equatable, Sendable {
        case mapTab, mySegments
    }

    var isPresented = false
    var toast: String?
    private(set) var entry = Entry.mapTab

    @ObservationIgnored private let isOnline: @MainActor () -> Bool

    init(isOnline: @escaping @MainActor () -> Bool) {
        self.isOnline = isOnline
    }

    func start(from entry: Entry) {
        guard isOnline() else {
            toast = SegmentMessages.connectionRequired
            return
        }
        self.entry = entry
        isPresented = true
    }
}

/// The Itinerary editor drawing a Segment, built by the app shell (features never build each
/// other's screens, ADR-007 rule 5): its screen, and the path it draws, read through
/// Observation so the card follows every change.
struct SegmentDrawingCanvas {
    let view: AnyView
    let drawing: @MainActor () -> SegmentDrawing
}
