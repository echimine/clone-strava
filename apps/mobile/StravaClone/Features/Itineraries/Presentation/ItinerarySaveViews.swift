import SwiftUI

/// "Enregistrer" under the editor's stats card: available once there is a start and a
/// finish and no Leg is still being computed; opens the naming sheet.
struct ItinerarySaveBar: View {
    @Bindable var store: ItinerarySaveStore
    let draft: ItineraryDraft
    let onSaved: () -> Void

    @State private var isNaming = false

    var body: some View {
        let blocker = store.blocker(for: draft)
        VStack(spacing: 6) {
            Button {
                isNaming = true
            } label: {
                Text("Enregistrer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(blocker != nil)
            .accessibilityIdentifier("saveItinerary")

            if let blocker, draft.waypoints.count >= 2 {
                Text(blocker)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.bottom, 8)
        .sheet(isPresented: $isNaming, onDismiss: store.dismissFailure) {
            ItineraryNameSheet(store: store, draft: draft, onCancel: { isNaming = false })
                .presentationDetents([.medium])
                .interactiveDismissDisabled(store.phase == .saving)
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .saved {
                isNaming = false
                onSaved()
            }
        }
    }
}

/// Names the Itinerary (1 to 100 characters) and saves it. A failure keeps the sheet open
/// with the reason, and a retry when one may succeed (e.g. `503` from the elevation provider).
struct ItineraryNameSheet: View {
    @Bindable var store: ItinerarySaveStore
    let draft: ItineraryDraft
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var isSaving: Bool { store.phase == .saving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom de l'Itinéraire", text: $store.name)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .disabled(isSaving)
                        .accessibilityIdentifier("itineraryName")
                } footer: {
                    Text("\(store.name.trimmingCharacters(in: .whitespacesAndNewlines).count)/100")
                        .monospacedDigit()
                }

                if case .failed(let message, let canRetry) = store.phase {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("itinerarySaveError")
                        if canRetry {
                            Button("Réessayer", action: save)
                                .accessibilityIdentifier("retrySaveItinerary")
                        }
                    }
                }
            }
            .navigationTitle("Enregistrer l'Itinéraire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Enregistrer", action: save)
                            .disabled(!store.isNameValid)
                            .accessibilityIdentifier("confirmSaveItinerary")
                    }
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func save() {
        guard store.isNameValid else { return }
        Task { await store.save(draft) }
    }
}
