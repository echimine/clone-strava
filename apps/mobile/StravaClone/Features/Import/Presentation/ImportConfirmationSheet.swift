import SwiftUI

/// Confirmation before sending (ADR-028 §3 overrides): sport, title and visibility,
/// each optional except the sport after an `unknown_sport` failure.
struct ImportConfirmationSheet: View {
    let confirmation: ImportStore.Confirmation
    let onConfirm: (ImportOptions) -> Void
    let onCancel: () -> Void

    @State private var sport: ImportSport?
    @State private var title = ""
    @State private var visibility: ImportVisibility?

    private var canConfirm: Bool {
        !confirmation.sportRequired || sport != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Fichier") {
                        Text(confirmation.file.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent(
                        "Taille",
                        value: Int64(confirmation.file.sizeBytes)
                            .formatted(.byteCount(style: .file).locale(Locale(identifier: "fr_FR")))
                    )
                }

                Section {
                    Picker("Sport", selection: $sport) {
                        if !confirmation.sportRequired {
                            Text("Détection automatique").tag(ImportSport?.none)
                        }
                        ForEach(ImportSport.allCases) { sport in
                            Text(ImportMessages.label(for: sport)).tag(Optional(sport))
                        }
                    }
                    .accessibilityIdentifier("import.sport")
                    TextField("Titre (facultatif)", text: $title)
                        .accessibilityIdentifier("import.title")
                    Picker("Visibilité", selection: $visibility) {
                        Text("Par défaut du profil").tag(ImportVisibility?.none)
                        ForEach(ImportVisibility.allCases) { visibility in
                            Text(ImportMessages.label(for: visibility)).tag(Optional(visibility))
                        }
                    }
                } footer: {
                    if confirmation.sportRequired {
                        Text("Le sport n'a pas pu être détecté dans le fichier.")
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importer") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onConfirm(ImportOptions(sport: sport, title: trimmed.isEmpty ? nil : trimmed, visibility: visibility))
                    }
                    .disabled(!canConfirm)
                    .accessibilityIdentifier("import.confirm")
                }
            }
            .onAppear {
                if confirmation.sportRequired && sport == nil {
                    sport = .run
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
