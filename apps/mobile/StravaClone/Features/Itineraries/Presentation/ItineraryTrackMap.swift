import MapboxMaps
import SwiftUI

/// The saved track on an Outdoors map, framed on it, with its start and finish markers
/// (ADR-030 §8). Offline, the map background comes from Mapbox's automatic cache with no
/// guarantee: the track is drawn locally underneath (`PolylineSketch`) until the map has
/// loaded, so it shows even when the background never does. Gestures are off: the map sits
/// in a scrolling page.
struct ItineraryTrackMap: View {
    let track: ItineraryTrack

    @State private var isMapLoaded = false

    var body: some View {
        let coordinates = track.polyline.decode()
        ZStack {
            sketch(coordinates)
            if coordinates.count >= 2 {
                map(coordinates)
                    .opacity(isMapLoaded ? 1 : 0)
            }
        }
        // A new track (edited, #37) is framed again.
        .id(track.polyline.value)
        .accessibilityElement()
        .accessibilityLabel("Carte de l'Itinéraire")
        .accessibilityIdentifier("itineraryTrackMap")
    }

    private func sketch(_ coordinates: [Coordinate]) -> some View {
        ZStack {
            Color(.tertiarySystemFill)
            PolylineSketch(coordinates: coordinates, inset: 32)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }

    private func map(_ coordinates: [Coordinate]) -> some View {
        let line = coordinates.map(\.locationCoordinate)
        return Map(initialViewport: .overview(
            geometry: LineString(line),
            geometryPadding: EdgeInsets(top: 40, leading: 32, bottom: 40, trailing: 32)
        )) {
            PolylineAnnotation(lineCoordinates: line)
                .lineColor(UIColor(Theme.accent))
                .lineWidth(4)
                .lineJoin(.round)
            RouteEndpointsContent(coordinates: line)
        }
        .mapStyle(.outdoors)
        .gestureOptions(GestureOptions(
            panEnabled: false,
            pinchEnabled: false,
            rotateEnabled: false,
            simultaneousRotateAndPinchZoomEnabled: false,
            pinchZoomEnabled: false,
            pinchPanEnabled: false,
            pitchEnabled: false,
            doubleTapToZoomInEnabled: false,
            doubleTouchToZoomOutEnabled: false,
            quickZoomEnabled: false
        ))
        .onMapLoaded { _ in isMapLoaded = true }
    }
}
