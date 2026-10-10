import Foundation
import Observation

/// Screen state of the Itinerary editor (ADR-030 §2): what the map draws, the stats card
/// and the messages, derived from the editor model.
@Observable
@MainActor
final class ItineraryEditorStore {
    struct Marker: Identifiable, Equatable {
        enum Role: Equatable {
            case start, waypoint, finish
        }

        let id: WaypointID
        let coordinate: Coordinate
        let role: Role
    }

    struct Line: Identifiable, Equatable {
        let id: LegID
        let coordinates: [Coordinate]
        /// Straight placeholder while the path is computed or pending: drawn dashed.
        let isProvisional: Bool
    }

    let editor: ItineraryEditor

    init(editor: ItineraryEditor) {
        self.editor = editor
    }

    // MARK: State

    var sportLabel: String {
        ActivityFormatters.sportLabel(editor.draft.sport.sportType)
    }

    var sportSymbol: String {
        ActivityFormatters.sportSymbol(editor.draft.sport.sportType)
    }

    var distanceText: String {
        ActivityFormatters.distance(editor.draft.distance)
    }

    var markers: [Marker] {
        let waypoints = editor.draft.waypoints
        return waypoints.enumerated().map { index, waypoint in
            let role: Marker.Role = index == 0 ? .start : (index == waypoints.count - 1 ? .finish : .waypoint)
            return Marker(id: waypoint.id, coordinate: waypoint.coordinate, role: role)
        }
    }

    var lines: [Line] {
        let draft = editor.draft
        return draft.legs.enumerated().map { index, leg in
            Line(
                id: leg.id,
                coordinates: draft.geometry(ofLegAt: index),
                isProvisional: leg.mode == .follow && leg.state != .computed
            )
        }
    }

    var hint: String? {
        switch editor.draft.waypoints.count {
        case 0: "Touchez la carte pour placer le départ."
        case 1: "Touchez la carte pour ajouter un point de passage."
        default: nil
        }
    }

    var message: String? {
        switch editor.notice {
        case .noPath: "Aucun chemin trouvé près de ce point : le tronçon passe en ligne droite."
        case .routingUnavailable: "Calcul du tracé impossible pour le moment : le tronçon est en attente."
        case .routingSaturated: "Le calcul des tracés est saturé : le tronçon est en attente."
        case nil: nil
        }
    }

    // MARK: Intents

    func tap(at coordinate: Coordinate) {
        editor.addWaypoint(at: coordinate)
    }

    func dismissMessage() {
        editor.dismissNotice()
    }
}
