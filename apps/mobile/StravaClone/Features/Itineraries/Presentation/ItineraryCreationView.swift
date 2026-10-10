import SwiftUI

/// "Créer" from the Map tab: the athlete picks a sport, then traces in the editor.
struct ItineraryCreationView: View {
    let makeEditorStore: @MainActor (ItinerarySport) -> ItineraryEditorStore
    let onClose: () -> Void

    @State private var editorStore: ItineraryEditorStore?

    var body: some View {
        if let editorStore {
            ItineraryEditorView(store: editorStore, onClose: onClose)
        } else {
            ItinerarySportPicker(onPick: { editorStore = makeEditorStore($0) }, onCancel: onClose)
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
