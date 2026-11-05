import MapboxMaps
import SwiftUI

/// A path drawn among others on a map (the Segments of a zone, ADR-039 §15), tappable.
struct MapPath: Identifiable, Equatable {
    let id: String
    let coordinates: [Coordinate]
}

/// Paths in dark grey; a tap on one reports its id.
struct MapPathsContent: MapContent {
    let paths: [MapPath]
    let onTap: (String) -> Void

    static let color = UIColor(red: 0.18, green: 0.2, blue: 0.3, alpha: 0.85)

    var body: some MapContent {
        PolylineAnnotationGroup(paths.filter { $0.coordinates.count >= 2 }) { path in
            PolylineAnnotation(lineCoordinates: path.coordinates.map(\.locationCoordinate))
                .lineColor(Self.color)
                .lineWidth(4)
                .onTapGesture { _ in
                    onTap(path.id)
                    return true
                }
        }
        .lineCap(.round)
        .lineJoin(.round)
    }
}
