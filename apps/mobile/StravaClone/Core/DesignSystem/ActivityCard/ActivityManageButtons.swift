import SwiftUI

/// The author's actions on a processed Activity (ADR-033 §1, §3): the same buttons in the
/// detail's "⋯" menu and in a feed card's context menu.
struct ActivityManageButtons: View {
    let onEdit: () -> Void

    var body: some View {
        Button("Modifier", systemImage: "pencil", action: onEdit)
            .accessibilityIdentifier("activity.edit")
    }
}
