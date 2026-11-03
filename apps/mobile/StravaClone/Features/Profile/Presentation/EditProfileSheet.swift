import SwiftUI

/// "Modifier le profil" (ADR-036 §3): first and last name, sent with `PATCH /v1/me/profile`.
/// Closes once the header shows the new name; a refusal stays on the sheet.
struct EditProfileSheet: View {
    let store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var error: String?
    @State private var isSaving = false

    init(store: ProfileStore, displayName: String) {
        self.store = store
        let parts = ProfileName.parts(of: displayName)
        _firstName = State(initialValue: parts.firstName)
        _lastName = State(initialValue: parts.lastName)
    }

    private var isValid: Bool { ProfileName(firstName: firstName, lastName: lastName) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(ProfileMessages.firstName, text: $firstName)
                        .textContentType(.givenName)
                        .accessibilityIdentifier("editProfile.firstName")
                    TextField(ProfileMessages.lastName, text: $lastName)
                        .textContentType(.familyName)
                        .accessibilityIdentifier("editProfile.lastName")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(ProfileMessages.editProfile)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProfileMessages.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(ProfileMessages.save) {
                            Task { await save() }
                        }
                        .disabled(!isValid)
                        .accessibilityIdentifier("editProfile.save")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        error = await store.rename(firstName: firstName, lastName: lastName)
        if error == nil {
            dismiss()
        }
    }
}
