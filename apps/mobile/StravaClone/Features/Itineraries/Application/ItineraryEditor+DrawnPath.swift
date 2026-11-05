import Foundation

extension ItineraryEditor {
    /// The drawn path in one line, once settled (no gesture, every Leg routed or straight): what
    /// the editor gives when it draws a Segment (ADR-039 §15). nil before a start and a finish,
    /// or while the path changes.
    var settledPath: [Coordinate]? {
        guard draggedWaypointID == nil, draft.geometry != nil else { return nil }
        var path: [Coordinate] = []
        for index in draft.legs.indices {
            let leg = draft.geometry(ofLegAt: index)
            path += path.last == leg.first ? Array(leg.dropFirst()) : leg
        }
        return path
    }

    /// Whether there is a start and a finish yet.
    var hasStartAndFinish: Bool {
        draft.waypoints.count >= 2
    }
}
