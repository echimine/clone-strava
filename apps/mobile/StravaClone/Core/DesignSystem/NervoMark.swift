import SwiftUI

/// The Nervo symbol "Col" (ADR-032 §2): an N drawn as one stroke, like a stage profile that
/// climbs, tips over and kicks again. Same geometry as the master SVG
/// `packages/ui/src/brand/nervo-symbol.svg`, in its 100 × 100 box scaled to fit the rect and
/// centered in it.
///
/// One open path, so `.trim(from:to:)` draws it like a pen (splash, celebration). Stroke it with
/// round caps and joins, at `lineWidth(forSide:)`:
///
///     NervoMark()
///         .stroke(.white, style: NervoMark.strokeStyle(forSide: 120))
///         .frame(width: 120, height: 120)
struct NervoMark: Shape {
    /// `M24 78 L24 24 L44 50 L51 42 L76 78 L76 22`, in the master's 100 × 100 box.
    static let points: [CGPoint] = [
        CGPoint(x: 24, y: 78), CGPoint(x: 24, y: 24), CGPoint(x: 44, y: 50),
        CGPoint(x: 51, y: 42), CGPoint(x: 76, y: 78), CGPoint(x: 76, y: 22),
    ]
    private static let box: CGFloat = 100
    private static let masterLineWidth: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / Self.box
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        var path = Path()
        path.addLines(Self.points.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) })
        return path
    }

    /// The master's stroke (10 in the 100 box) for a mark drawn `side` points wide.
    static func lineWidth(forSide side: CGFloat) -> CGFloat {
        side * masterLineWidth / box
    }

    static func strokeStyle(forSide side: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth(forSide: side), lineCap: .round, lineJoin: .round)
    }
}

#Preview {
    NervoMark()
        .stroke(.white, style: NervoMark.strokeStyle(forSide: 180))
        .frame(width: 180, height: 180)
        .background(Theme.accent, in: .rect(cornerRadius: 40))
}
