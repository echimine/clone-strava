import SwiftUI

/// Renommer and Supprimer on the detail page (ADR-030 §8), online or not: rename without
/// opening the editor, delete once confirmed. Both show at once; the queue sends them later.
struct ItineraryManageMenu: View {
    let store: ItineraryDetailStore

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        Menu {
            Button {
                draftName = store.summary?.name ?? ""
                isRenaming = true
            } label: {
                Label(ItineraryMessages.rename, systemImage: "pencil")
            }
            .accessibilityIdentifier("renameItinerary")
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label(ItineraryMessages.delete, systemImage: "trash")
            }
            .accessibilityIdentifier("deleteItinerary")
        } label: {
            Label(ItineraryMessages.actions, systemImage: "ellipsis.circle")
        }
        .disabled(store.summary == nil)
        .accessibilityIdentifier("itineraryActions")
        .alert(ItineraryMessages.renameTitle, isPresented: $isRenaming) {
            TextField(ItineraryMessages.namePlaceholder, text: $draftName)
                .accessibilityIdentifier("itineraryNameField")
            Button(ItineraryMessages.cancel, role: .cancel) {}
            Button(ItineraryMessages.rename) {
                let name = draftName
                Task { _ = await store.rename(to: name) }
            }
            .disabled(!ItineraryDetailStore.isValidName(draftName))
        } message: {
            Text(ItineraryMessages.saveIssue(.invalidName))
        }
        .confirmationDialog(ItineraryMessages.deleteTitle, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(ItineraryMessages.delete, role: .destructive) {
                Task { await store.delete() }
            }
            Button(ItineraryMessages.cancel, role: .cancel) {}
        } message: {
            Text(ItineraryMessages.deleteMessage)
        }
    }
}
