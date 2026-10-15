import MapboxMaps
import SwiftUI

/// Map view of the Recording (ADR-031 §8): the Itinerary track wide and translucent, the
/// recorded trace solid, the Return path dotted, and the position puck following the athlete.
struct RecordingLiveMap: View {
    let trace: [Coordinate]
    var itineraryTrack: [Coordinate] = []
    var returnPath: [Coordinate] = []

    @State private var viewport = Viewport.followUser

    var body: some View {
        AppMap(viewport: $viewport, bottomInset: 110) {
            ItineraryTrackLine(track: itineraryTrack)
            PolylineAnnotationGroup(returnPath.count >= 2 ? [ReturnPathLine(coordinates: returnPath)] : []) { line in
                PolylineAnnotation(lineCoordinates: line.coordinates.map(\.locationCoordinate))
                    .lineColor(UIColor(Theme.accent))
                    .lineWidth(4)
            }
            .lineDashArray([1, 1.5])
            .lineCap(.round)
            if trace.count >= 2 {
                PolylineAnnotation(lineCoordinates: trace.map(\.locationCoordinate))
                    .lineColor(UIColor(Theme.accent))
                    .lineWidth(5)
                    .lineJoin(.round)
            }
        }
        .accessibilityIdentifier("recordingMap")
    }
}

/// The Return path drawn on the map: one line, replaced when a new one arrives.
private struct ReturnPathLine: Identifiable {
    let coordinates: [Coordinate]
    var id: [Coordinate] { coordinates }
}

/// Mini-map of the finish screen (ADR-031 §11): the trace framed, start and finish markers.
/// The sketch shows underneath until the map has loaded (offline).
struct RecordingTraceMap: View {
    let trace: [Coordinate]

    @State private var isMapLoaded = false

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            PolylineSketch(coordinates: trace, inset: 24)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            if trace.count >= 2 {
                map.opacity(isMapLoaded ? 1 : 0)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Carte de la trace")
        .accessibilityIdentifier("recordingTraceMap")
    }

    private var map: some View {
        let line = trace.map(\.locationCoordinate)
        return Map(initialViewport: .overview(
            geometry: LineString(line),
            geometryPadding: EdgeInsets(top: 32, leading: 24, bottom: 32, trailing: 24)
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

/// The followed Itinerary's track (ADR-031 §8): wide and translucent, under the recorded trace.
struct ItineraryTrackLine: MapContent {
    let track: [Coordinate]

    var body: some MapContent {
        if track.count >= 2 {
            PolylineAnnotation(lineCoordinates: track.map(\.locationCoordinate))
                .lineColor(UIColor(Theme.accent).withAlphaComponent(0.35))
                .lineWidth(10)
                .lineJoin(.round)
        }
    }
}
