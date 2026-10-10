import SwiftUI

/// The detail page pushed from Mes Itinéraires, with "Modifier" in its toolbar (#37): the
/// editor reopens full screen on the saved Itinerary, and once saved the page shows the edit
/// at once (the detail observes the cache). Offline, "Modifier" shows "Connexion requise".
struct ItineraryDetailPage: View {
    @State private var detailStore: ItineraryDetailStore
    @State private var editFlow: ItineraryEditFlow

    init(
        id: ItineraryID,
        makeDetailStore: @MainActor (ItineraryID) -> ItineraryDetailStore,
        makeEditFlow: @MainActor (ItineraryID) -> ItineraryEditFlow
    ) {
        _detailStore = State(initialValue: makeDetailStore(id))
        _editFlow = State(initialValue: makeEditFlow(id))
    }

    var body: some View {
        ItineraryDetailView(store: detailStore) {
            Button {
                Task { await editFlow.start() }
            } label: {
                if editFlow.isLoading {
                    ProgressView()
                } else {
                    Text(ItineraryMessages.edit)
                }
            }
            .disabled(editFlow.isLoading)
            .accessibilityIdentifier("editItinerary")
        }
        .toast($editFlow.toast)
        .fullScreenCover(item: $editFlow.session) { session in
            ItineraryEditingView(session: session, onClose: editFlow.close)
        }
    }
}

/// The editor reopened on a saved Itinerary, "Enregistrer" replacing it on the same id.
struct ItineraryEditingView: View {
    let session: ItineraryEditFlow.Session
    let onClose: () -> Void

    var body: some View {
        ItineraryEditorView(store: session.editorStore, onClose: onClose)
            .safeAreaInset(edge: .bottom) {
                ItinerarySaveBar(store: session.saveStore, draft: session.editorStore.editor.draft, onSaved: onClose)
            }
    }
}
