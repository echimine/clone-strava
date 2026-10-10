import SwiftUI

/// "Créer" from the Map tab or Mes Itinéraires: the athlete picks a sport, traces in the
/// editor, then saves. The Itinerary's id is generated when the editor opens (ADR-030 §6).
struct ItineraryCreationView: View {
    let makeEditorStore: @MainActor (ItinerarySport) -> ItineraryEditorStore
    let makeSaveStore: @MainActor () -> ItinerarySaveStore
    let onClose: () -> Void

    @State private var editorStore: ItineraryEditorStore?
    @State private var saveStore: ItinerarySaveStore?

    var body: some View {
        if let editorStore, let saveStore {
            ItineraryEditorView(store: editorStore, onClose: onClose)
                .safeAreaInset(edge: .bottom) {
                    ItinerarySaveBar(store: saveStore, draft: editorStore.editor.draft, onSaved: onClose)
                }
        } else {
            ItinerarySportPicker(
                onPick: { sport in
                    saveStore = makeSaveStore()
                    editorStore = makeEditorStore(sport)
                },
                onCancel: onClose
            )
        }
    }
}

/// Sports an Itinerary can be planned for; swimming is never offered.
struct ItinerarySportPicker: View {
    let onPick: (ItinerarySport) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ItinerarySport.allCases, id: \.self) { sport in
                        Button {
                            onPick(sport)
                        } label: {
                            Label(
                                ActivityFormatters.sportLabel(sport.sportType),
                                systemImage: ActivityFormatters.sportSymbol(sport.sportType)
                            )
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("itinerarySport.\(sport.rawValue)")
                    }
                } header: {
                    Text("Choisissez un sport")
                } footer: {
                    Text("Le tracé suit les routes et les sentiers adaptés au sport.")
                }
            }
            .navigationTitle("Nouvel Itinéraire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
            }
        }
    }
}
