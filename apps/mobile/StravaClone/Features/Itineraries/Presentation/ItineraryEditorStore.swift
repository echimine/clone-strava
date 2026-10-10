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
        /// Path not final yet, computed or pending: drawn dashed, as a straight placeholder or
        /// the former path while recomputed for a new sport.
        let isProvisional: Bool
    }

    /// Handle in the middle of a Leg: pulling it inserts a Waypoint there.
    struct InsertionHandle: Identifiable, Equatable {
        let id: LegID
        let coordinate: Coordinate
    }

    /// What a bubble is open on.
    enum Selection: Equatable {
        /// Offers "Supprimer".
        case waypoint(WaypointID)
        /// Offers the Leg's mode, anchored where the Leg was tapped.
        case leg(LegID, at: Coordinate)
    }

    /// Finger moves shorter than this, in points, are ignored: the Waypoint is resting.
    static let dragTolerance: CGFloat = 8

    let editor: ItineraryEditor
    private(set) var selection: Selection?
    @ObservationIgnored private var lastDragPoint: CGPoint?
    @ObservationIgnored private let connectivityChanges: @MainActor () -> AsyncStream<Bool>

    /// - Parameter connectivityChanges: `true` while a network route exists, current state first.
    init(
        editor: ItineraryEditor,
        connectivityChanges: @escaping @MainActor () -> AsyncStream<Bool> = { AsyncStream { $0.finish() } }
    ) {
        self.editor = editor
        self.connectivityChanges = connectivityChanges
    }

    // MARK: State

    var sport: ItinerarySport {
        editor.draft.sport
    }

    var sportLabel: String {
        ActivityFormatters.sportLabel(editor.draft.sport.sportType)
    }

    var sportSymbol: String {
        ActivityFormatters.sportSymbol(editor.draft.sport.sportType)
    }

    var distanceText: String {
        ActivityFormatters.distance(editor.displayedDraft.distance)
    }

    /// While the finger moves, the distance runs on straight placeholders: shown greyed out
    /// until the next pause or the release.
    var isDistanceStale: Bool {
        editor.draggedWaypointID != nil && lines.contains(where: \.isProvisional)
    }

    /// Waypoints where they are, a dragged one under the finger.
    var markers: [Marker] {
        let waypoints = editor.draft.waypoints
        return waypoints.enumerated().map { index, waypoint in
            let role: Marker.Role = index == 0 ? .start : (index == waypoints.count - 1 ? .finish : .waypoint)
            return Marker(id: waypoint.id, coordinate: waypoint.coordinate, role: role)
        }
    }

    var lines: [Line] {
        let draft = editor.displayedDraft
        return draft.legs.enumerated().map { index, leg in
            Line(
                id: leg.id,
                coordinates: draft.geometry(ofLegAt: index),
                isProvisional: leg.mode == .follow && leg.state != .computed
            )
        }
    }

    /// During a pause in a drag, the routed path stops at the snapped position: a dashed
    /// line joins it to the finger.
    var snapConnector: [Coordinate]? {
        guard let id = editor.draggedWaypointID,
              let finger = editor.draft.waypoints.first(where: { $0.id == id })?.coordinate,
              let snapped = editor.displayedDraft.waypoints.first(where: { $0.id == id })?.coordinate,
              snapped != finger
        else { return nil }
        return [snapped, finger]
    }

    /// Handles stay in `insertionHandles` during a drag, so the pulled one keeps its gesture,
    /// but are not shown.
    var showsInsertionHandles: Bool {
        editor.draggedWaypointID == nil
    }

    var insertionHandles: [InsertionHandle] {
        let draft = editor.draft
        return draft.legs.indices.map { index in
            InsertionHandle(id: draft.legs[index].id, coordinate: Self.midpoint(of: draft.geometry(ofLegAt: index)))
        }
    }

    var selectedLegMode: LegMode? {
        guard case .leg(let id, _) = selection else { return nil }
        return editor.draft.legs.first(where: { $0.id == id })?.mode
    }

    var canUndo: Bool {
        editor.canUndo
    }

    var canRedo: Bool {
        editor.canRedo
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
        case .routingUnavailable:
            "Calcul du tracé impossible pour le moment : le tronçon est en attente et sera recalculé au retour du réseau."
        case .routingSaturated:
            "Le service de calcul des tracés est momentanément saturé : le tronçon est en attente et sera recalculé automatiquement."
        case .waypointLimitReached:
            "Limite de \(ItineraryDraft.maxWaypoints) points de passage atteinte : supprimez-en un pour en ajouter un autre."
        case nil: nil
        }
    }

    /// "Réessayer" next to the message, while a Leg is pending and no backoff is under way.
    var canRetryPendingLegs: Bool {
        editor.canRetryPendingLegs
    }

    // MARK: Intents

    /// Tap on the map: closes an open bubble, or adds a Waypoint at the end.
    func tap(at coordinate: Coordinate) {
        guard selection == nil else {
            selection = nil
            return
        }
        editor.addWaypoint(at: coordinate)
    }

    func tapWaypoint(_ id: WaypointID) {
        selection = selection == .waypoint(id) ? nil : .waypoint(id)
    }

    func tapLeg(_ id: LegID, at coordinate: Coordinate) {
        selection = .leg(id, at: coordinate)
    }

    func dismissSelection() {
        selection = nil
    }

    func removeSelectedWaypoint() {
        guard case .waypoint(let id) = selection else { return }
        selection = nil
        editor.removeWaypoint(id)
    }

    func setSelectedLegMode(_ mode: LegMode) {
        guard case .leg(let id, _) = selection else { return }
        selection = nil
        editor.setMode(mode, ofLeg: id)
    }

    func beginDrag(_ id: WaypointID, at point: CGPoint) {
        selection = nil
        lastDragPoint = point
        editor.beginDrag(id)
    }

    func beginInsertion(intoLeg id: LegID, at coordinate: Coordinate, point: CGPoint) {
        selection = nil
        lastDragPoint = point
        editor.beginInsertion(intoLeg: id, at: coordinate)
    }

    func drag(to coordinate: Coordinate, at point: CGPoint) {
        if let lastDragPoint, hypot(point.x - lastDragPoint.x, point.y - lastDragPoint.y) < Self.dragTolerance {
            return
        }
        lastDragPoint = point
        editor.drag(to: coordinate)
    }

    func endDrag(at coordinate: Coordinate, point: CGPoint) {
        drag(to: coordinate, at: point)
        lastDragPoint = nil
        editor.endDrag()
    }

    /// Another sport picked in the stats card: in another category, the Legs that follow
    /// roads and trails are recomputed while editing goes on.
    func changeSport(to sport: ItinerarySport) {
        selection = nil
        editor.changeSport(to: sport)
    }

    func undo() {
        selection = nil
        editor.undo()
    }

    func redo() {
        selection = nil
        editor.redo()
    }

    func dismissMessage() {
        editor.dismissNotice()
    }

    func retryPendingLegs() {
        editor.retryPendingLegs()
    }

    /// For as long as the screen is shown: pending Legs are requested again when the network
    /// comes back (ADR-030 §2).
    func retryPendingLegsOnReconnection() async {
        await editor.retryPendingLegs(onReconnectionOf: connectivityChanges())
    }

    // MARK: Private

    /// Point halfway along a line.
    private static func midpoint(of line: [Coordinate]) -> Coordinate {
        let segments = Array(zip(line, line.dropFirst()))
        var remaining = segments.reduce(0) { $0 + $1.0.distance(to: $1.1).meters } / 2
        for (start, end) in segments {
            let length = start.distance(to: end).meters
            if length > 0, remaining <= length {
                let fraction = remaining / length
                return Coordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                )
            }
            remaining -= length
        }
        return line[0]
    }
}
