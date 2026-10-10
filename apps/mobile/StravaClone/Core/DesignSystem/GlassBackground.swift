import SwiftUI

extension View {
    /// Liquid Glass on iOS 26 (interactive: it reacts to touches, for buttons and cards),
    /// material before.
    func glassBackground<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: shape, interactive: interactive))
    }
}

private struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
