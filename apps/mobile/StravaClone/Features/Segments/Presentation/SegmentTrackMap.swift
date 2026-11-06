import MapboxMaps
import SwiftUI

/// The Segment's path in orange on an Outdoors map, framed on it, with its start and finish
/// (ADR-039 §15). The path is sketched underneath until the map loads; gestures are off, the
/// map sits in a scrolling page. Shown by the sheet and by the preview of a creation.
struct SegmentTrackMap: View {
    let coordinates: [Coordinate]

    @State private var isMapLoaded = false

    init(track: SegmentTrack) {
        coordinates = track.coordinates
    }

    /// The resampled path of a creation's preview.
    init(track: [Coordinate]) {
        coordinates = track
    }

    var body: some View {
        ZStack {
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
        .accessibilityElement()
        .accessibilityLabel("Carte du Segment")
        .accessibilityIdentifier("segmentTrackMap")
    }

    private func map(_ line: [CLLocationCoordinate2D]) -> some View {
        Map(initialViewport: .overview(
            geometry: LineString(line),
            geometryPadding: EdgeInsets(top: 40, leading: 32, bottom: 40, trailing: 32)
        )) {
            PolylineAnnotation(lineCoordinates: line)
                .lineColor(UIColor(Theme.accent))
                .lineWidth(5)
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
