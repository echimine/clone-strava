import CoreGraphics
import SwiftUI
import Testing
@testable import StravaClone

/// The Nervo symbol "Col" (ADR-032 §2), checked against the master SVG
/// `packages/ui/src/brand/nervo-symbol.svg`: `M24 78 L24 24 L44 50 L51 42 L76 78 L76 22` in a 100 × 100 box.
struct NervoMarkTests {
    private func expectClose(_ rect: CGRect, _ expected: CGRect) {
        let gaps = [rect.minX - expected.minX, rect.minY - expected.minY, rect.width - expected.width, rect.height - expected.height]
        #expect(gaps.allSatisfy { abs($0) < 1e-6 }, "\(rect) ≠ \(expected)")
    }

    @Test func inTheMasterBoxThePathSpansTheSvgGeometry() {
        let path = NervoMark().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        expectClose(path.boundingRect, CGRect(x: 24, y: 22, width: 52, height: 56))
    }

    @Test func theBoxIsScaledToFitAndCenteredInTheRect() {
        let path = NervoMark().path(in: CGRect(x: 10, y: 0, width: 400, height: 200))
        // 200 pt square, centered horizontally: the box starts at x = 10 + 100.
        expectClose(path.boundingRect, CGRect(x: 110 + 48, y: 44, width: 104, height: 112))
    }

    /// One open stroke, from the bottom left to the top right, so `.trim` draws it like a pen.
    @Test func thePathIsOneOpenStrokeFromTheBottomLeftToTheTopRight() {
        var elements: [Path.Element] = []
        NervoMark().path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).forEach { elements.append($0) }
        #expect(elements.first == .move(to: CGPoint(x: 24, y: 78)))
        #expect(elements.last == .line(to: CGPoint(x: 76, y: 22)))
        #expect(!elements.contains(.closeSubpath))
        #expect(elements.count == 6)
    }

    /// The stroke is 10 in the 100 box: it scales with the drawn size.
    @Test func theLineWidthIsATenthOfTheSide() {
        #expect(NervoMark.lineWidth(forSide: 100) == 10)
        #expect(NervoMark.lineWidth(forSide: 240) == 24)
    }
}
