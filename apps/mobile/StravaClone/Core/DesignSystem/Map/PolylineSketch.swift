import SwiftUI

/// A path drawn without a map (ADR-030 §8): the thumbnail shown when the static map image
/// is missing (offline, no token). North is up and distances keep their proportions.
struct PolylineSketch: Shape {
    let coordinates: [Coordinate]
    var inset: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let points = Self.points(coordinates, in: rect.insetBy(dx: inset, dy: inset))
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    /// Equirectangular projection at the path's mean latitude, scaled to fit `rect` and
    /// centered in it. Empty for fewer than two points.
    static func points(_ coordinates: [Coordinate], in rect: CGRect) -> [CGPoint] {
        guard coordinates.count >= 2 else { return [] }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min()!, maxLat = latitudes.max()!
        let minLon = longitudes.min()!, maxLon = longitudes.max()!
        let lonScale = cos((minLat + maxLat) / 2 * .pi / 180)
        let width = (maxLon - minLon) * lonScale
        let height = maxLat - minLat
        guard width > 0 || height > 0 else { return [] }
        let scale = min(
            width > 0 ? rect.width / width : .infinity,
            height > 0 ? rect.height / height : .infinity
        )
        let originX = rect.midX - width * scale / 2
        let originY = rect.midY + height * scale / 2
        return coordinates.map { coordinate in
            CGPoint(
                x: originX + (coordinate.longitude - minLon) * lonScale * scale,
                y: originY - (coordinate.latitude - minLat) * scale
            )
        }
    }
}
