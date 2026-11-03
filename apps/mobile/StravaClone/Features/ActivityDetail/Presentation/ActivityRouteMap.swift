import MapboxMaps
import SwiftUI

/// The Activity's privacy-zoned polyline (ADR-029 §3) on an Outdoors map: camera framed on
/// the trace, start and finish markers (ADR-033 §3). The detail shows it without gestures;
/// panning and zooming happen on the full-screen map (ADR-036 §9).
struct ActivityRouteMap: View {
    let route: EncodedPolyline

    @State private var isMapLoaded = false

    var body: some View {
        let coordinates = route.decode()
        ZStack {
            // Drawn locally until the map has loaded, so the trace shows even offline.
            ZStack {
                Color(.tertiarySystemFill)
                PolylineSketch(coordinates: coordinates, inset: 32)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if coordinates.count >= 2 {
                map(coordinates.map(\.locationCoordinate))
                    .opacity(isMapLoaded ? 1 : 0)
            }
        }
        // A new trace (reprocessed after a sport change) is framed again.
        .id(route.value)
        .accessibilityElement()
        .accessibilityLabel("Carte de l'activité")
        .accessibilityIdentifier("activityDetail.map")
    }

    private func map(_ line: [CLLocationCoordinate2D]) -> some View {
        Map(initialViewport: .overview(
            geometry: LineString(line),
            geometryPadding: EdgeInsets(top: 48, leading: 32, bottom: 48, trailing: 32)
        )) {
            PolylineAnnotation(lineCoordinates: line)
                .lineColor(UIColor(Theme.accent))
                .lineWidth(4)
                .lineJoin(.round)
            RouteEndpointsContent(coordinates: line)
        }
        .mapStyle(.outdoors)
        // Pan and zoom; no rotation or pitch, the trace stays north up.
        .gestureOptions(GestureOptions(rotateEnabled: false, pitchEnabled: false))
        .onMapLoaded { _ in isMapLoaded = true }
    }
}
