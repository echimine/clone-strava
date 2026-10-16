import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import StravaClone

/// The Nervo symbol "Col" (ADR-032 §2), checked against the master SVG
/// `packages/ui/src/brand/nervo-symbol.svg`, copied into the test bundle (`project.yml`).
struct NervoMarkTests {
    /// The master's one path: its points (`M x y L x y …`) and stroke width, in its 100 × 100 box.
    private struct Master {
        let points: [CGPoint]
        let strokeWidth: CGFloat

        static func load() throws -> Master {
            let url = try #require(Bundle(for: BundleToken.self).url(forResource: "nervo-symbol", withExtension: "svg"))
            let svg = try String(contentsOf: url, encoding: .utf8)
            let path = String(try #require(svg.firstMatch(of: /<path[^>]*\sd="([^"]+)"/)?.1))
            let width = String(try #require(svg.firstMatch(of: /<path[^>]*\sstroke-width="([^"]+)"/)?.1))
            #expect(path.hasPrefix("M") && path.allSatisfy { "ML0123456789. ,-".contains($0) }, "only M and L commands: \(path)")
            let numbers = path.split(whereSeparator: { " ,ML".contains($0) }).compactMap { Double($0) }
            let points = stride(from: 0, to: numbers.count - 1, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) }
            return Master(points: points, strokeWidth: try #require(Double(width)))
        }
    }

    private func elements(_ path: Path) -> [Path.Element] {
        var elements: [Path.Element] = []
        path.forEach { elements.append($0) }
        return elements
    }

    /// `elements` is one open stroke through `points`: a move, then lines, no close.
    private func expectStroke(_ elements: [Path.Element], through points: [CGPoint], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(points.count > 1, sourceLocation: sourceLocation)
        let expected: [Path.Element] = points.enumerated().map { $0.offset == 0 ? .move(to: $0.element) : .line(to: $0.element) }
        #expect(elements.count == expected.count, sourceLocation: sourceLocation)
        for (element, target) in zip(elements, expected) {
            switch (element, target) {
            case let (.move(a), .move(b)), let (.line(a), .line(b)):
                #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6, "\(element) ≠ \(target)", sourceLocation: sourceLocation)
            default:
                Issue.record("\(element) ≠ \(target)", sourceLocation: sourceLocation)
            }
        }
    }

    /// One open stroke through the master's points, so `.trim` draws it like a pen.
    @Test func inTheMasterBoxThePathIsTheMasterSvgPath() throws {
        let master = try Master.load()
        expectStroke(elements(NervoMark().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))), through: master.points)
    }

    @Test func theBoxIsScaledToFitAndCenteredInTheRect() throws {
        let master = try Master.load()
        // A 200 pt square, centered horizontally: the box starts at (110, 0), twice as large.
        let scaled = master.points.map { CGPoint(x: 110 + 2 * $0.x, y: 2 * $0.y) }
        expectStroke(elements(NervoMark().path(in: CGRect(x: 10, y: 0, width: 400, height: 200))), through: scaled)
    }

    /// The stroke is the master's in the 100 box: it scales with the drawn size.
    @Test func theLineWidthIsTheMasterStrokeScaledToTheSide() throws {
        let master = try Master.load()
        #expect(NervoMark.lineWidth(forSide: 100) == master.strokeWidth)
        #expect(abs(NervoMark.lineWidth(forSide: 240) - master.strokeWidth * 2.4) < 1e-9)
    }
}

private final class BundleToken {}
