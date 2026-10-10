import SwiftUI

/// Heights of a two-detent bottom sheet: collapsed at a fraction of the available height,
/// expanded up to `topMargin` below the top. Translations are a drag's, negative upwards.
struct BottomSheetLayout: Equatable {
    let availableHeight: CGFloat
    let collapsedFraction: CGFloat
    let topMargin: CGFloat

    private var collapsedHeight: CGFloat { (availableHeight * collapsedFraction).rounded() }
    private var expandedHeight: CGFloat { max(collapsedHeight, availableHeight - topMargin) }

    /// Height while resting (`dragTranslation` 0) or following a finger, never past a detent.
    func height(isExpanded: Bool, dragTranslation: CGFloat = 0) -> CGFloat {
        let resting = isExpanded ? expandedHeight : collapsedHeight
        return min(max(resting - dragTranslation, collapsedHeight), expandedHeight)
    }

    /// Detent where a drag lands: the one closest to where its momentum would take the sheet.
    func settlesExpanded(wasExpanded: Bool, predictedTranslation: CGFloat) -> Bool {
        let projected = height(isExpanded: wasExpanded) - predictedTranslation
        return projected > (collapsedHeight + expandedHeight) / 2
    }
}

/// Sheet laid over a full-screen view without covering the tab bar (unlike `.sheet`), so the
/// other tabs stay reachable. Collapsed, the content does not scroll: dragging it, a list
/// included, opens the sheet in full; expanded, the content scrolls and the grabber closes it.
struct BottomSheet<Content: View>: View {
    @Binding var isExpanded: Bool
    let layout: BottomSheetLayout
    @ViewBuilder let content: () -> Content

    @GestureState private var translation: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            grabber
            content()
                .scrollDisabled(!isExpanded)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                // Simultaneous: a ScrollView, even with scrolling disabled, would win otherwise.
                .simultaneousGesture(drag, including: isExpanded ? .subviews : .all)
        }
        .frame(height: layout.height(isExpanded: isExpanded, dragTranslation: translation))
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground), in: shape)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
        .animation(.snappy, value: isExpanded)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(drag)
            .onTapGesture { isExpanded.toggle() }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isExpanded ? "Réduire" : "Agrandir")
            .accessibilityAction { isExpanded.toggle() }
            .accessibilityIdentifier("bottomSheetGrabber")
    }

    private var drag: some Gesture {
        // Global: the sheet grows under the finger, local translations would cancel out.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($translation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                isExpanded = layout.settlesExpanded(
                    wasExpanded: isExpanded,
                    predictedTranslation: value.predictedEndTranslation.height
                )
            }
    }
}
