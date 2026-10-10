import Foundation

extension ItineraryDraft {
    /// What `metrics-preview` measures: the full track, once there is a start and a finish
    /// and every `follow` Leg has its path. `nil` while a Leg is computing or pending.
    var metricsRequest: ItineraryMetricsRequest? {
        guard waypoints.count >= 2 else { return nil }
        var requestLegs: [ItineraryMetricsRequest.Leg] = []
        for leg in legs {
            switch (leg.mode, leg.state, leg.path) {
            case (.straight, _, _):
                requestLegs.append(.straight)
            case (.follow, .computed, let path?):
                requestLegs.append(.follow(EncodedPolyline(encoding: path, precision: 6)))
            case (.follow, _, _):
                return nil
            }
        }
        return ItineraryMetricsRequest(waypoints: waypoints.map(\.coordinate), legs: requestLegs)
    }
}
