import MapboxMaps
import SwiftUI

/// Start or finish of a path on a map: a green circle with a "play" sign, a red one with a
/// chequered flag.
enum RouteEndpoint {
    case start
    case finish

    var color: Color {
        switch self {
        case .start: Color(red: 0.18, green: 0.8, blue: 0.44)
        case .finish: Color(red: 0.91, green: 0.3, blue: 0.24)
        }
    }

    var symbol: String {
        switch self {
        case .start: "play.fill"
        case .finish: "flag.checkered"
        }
    }

    var label: String {
        switch self {
        case .start: "Départ"
        case .finish: "Arrivée"
        }
    }
}

struct RouteEndpointMarker: View {
    let endpoint: RouteEndpoint

    var body: some View {
        Image(systemName: endpoint.symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(endpoint.color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 1)
            .accessibilityLabel(endpoint.label)
    }
}

/// The start and finish markers of a drawn path, not touchable. They stay visible over the
/// user puck: a path usually starts where the athlete stands.
struct RouteEndpointsContent: MapContent {
    let coordinates: [CLLocationCoordinate2D]
    /// Below 1 while they fade in.
    var opacity: Double = 1

    var body: some MapContent {
        if let start = coordinates.first, let finish = coordinates.last {
            marker(.start, at: start)
            // Above the start: on a loop, the finish shows.
            marker(.finish, at: finish)
        }
    }

    private func marker(_ endpoint: RouteEndpoint, at coordinate: CLLocationCoordinate2D) -> MapViewAnnotation {
        MapViewAnnotation(coordinate: coordinate) {
            RouteEndpointMarker(endpoint: endpoint)
                .opacity(opacity)
        }
        .allowOverlap(true)
        .allowOverlapWithPuck(true)
        .allowHitTesting(false)
        .priority(endpoint == .finish ? 1 : 0)
    }
}
