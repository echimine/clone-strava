import CoreGraphics
import Foundation
import Testing
@testable import StravaClone

/// The thumbnail drawn locally when the static map is missing (offline, no token, ADR-030 §8).
struct PolylineSketchTests {
    private func expectClose(_ points: [CGPoint], _ expected: [CGPoint]) {
        #expect(points.count == expected.count)
        for (point, target) in zip(points, expected) {
            #expect(abs(point.x - target.x) < 1e-6 && abs(point.y - target.y) < 1e-6, "\(point) ≠ \(target)")
        }
    }

    /// At 60° N a degree of longitude is half a degree of latitude: an east-west line of 2°
    /// is as long as 1° north-south, and fills the width, centered vertically.
    @Test func anEastWestLineFillsTheWidthAtItsTrueProportions() {
        let points = PolylineSketch.points(
            [Coordinate(latitude: 60, longitude: 0), Coordinate(latitude: 60, longitude: 2)],
            in: CGRect(x: 0, y: 0, width: 100, height: 50)
        )
        expectClose(points, [CGPoint(x: 0, y: 25), CGPoint(x: 100, y: 25)])
    }

    @Test func northIsUpAndThePathIsCenteredInTheRect() {
        let points = PolylineSketch.points(
            [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 1, longitude: 0)],
            in: CGRect(x: 10, y: 10, width: 100, height: 50)
        )
        expectClose(points, [CGPoint(x: 60, y: 60), CGPoint(x: 60, y: 10)])
    }

    @Test func nothingIsDrawnForLessThanTwoPoints() {
        #expect(PolylineSketch.points([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        #expect(PolylineSketch.points([Coordinate(latitude: 1, longitude: 1)], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }
}
