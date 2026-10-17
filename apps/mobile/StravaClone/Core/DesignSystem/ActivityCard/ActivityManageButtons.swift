import SwiftUI

/// The author's actions on a processed Activity (ADR-033 §1, §3): the same buttons in the
/// detail's "⋯" menu and in a feed card's context menu. "Supprimer" only asks: the screen
/// confirms with `activityDeleteConfirmation`.
struct ActivityManageButtons: View {
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Modifier", systemImage: "pencil", action: onEdit)
            .accessibilityIdentifier("activity.edit")
        Button("Supprimer", systemImage: "trash", role: .destructive, action: onDelete)
            .accessibilityIdentifier("activity.delete")
    }
}

extension View {
    /// "Supprimer cette activité ? Cette action est irréversible." (ADR-033 §7), shown while
    /// `activity` is set; `onConfirm` gets it.
    func activityDeleteConfirmation(_ activity: Binding<ActivityID?>, onConfirm: @escaping (ActivityID) -> Void) -> some View {
        confirmationDialog(
            "Supprimer cette activité ?",
            isPresented: Binding(get: { activity.wrappedValue != nil }, set: { if !$0 { activity.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: activity.wrappedValue
        ) { id in
            Button("Supprimer", role: .destructive) { onConfirm(id) }
                .accessibilityIdentifier("activity.delete.confirm")
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Cette action est irréversible.")
        }
    }
}
