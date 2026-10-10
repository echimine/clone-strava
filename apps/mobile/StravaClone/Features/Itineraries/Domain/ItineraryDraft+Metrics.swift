import Foundation

extension ItineraryDraft {
    /// The `{ waypoints, legs }` sent to the API (`metrics-preview`, save), once there is a
    /// start and a finish and every `follow` Leg has its path. `nil` while a Leg is
    /// computing or pending.
    var geometry: ItineraryGeometry? {
        guard waypoints.count >= 2 else { return nil }
        var geometryLegs: [ItineraryGeometry.Leg] = []
        for leg in legs {
            switch (leg.mode, leg.state, leg.path) {
            case (.straight, _, _):
                geometryLegs.append(.straight)
            case (.follow, .computed, let path?):
                geometryLegs.append(.follow(EncodedPolyline(encoding: path, precision: 6)))
            case (.follow, _, _):
                return nil
            }
        }
        return ItineraryGeometry(waypoints: waypoints.map(\.coordinate), legs: geometryLegs)
    }
}
