import SwiftUI

/// "Modifier le profil" (ADR-036 §3), laid out like Strava's "Profil": my photo next to first and
/// last name, then Bio, Ville, Pays, Sport principal, and the athlete information (birth date,
/// sex, weight). Starts from `GET /v1/me/profile`, sends everything with "Enregistrer" and closes
/// once the header shows the new name; a refusal stays on the sheet. The photo is sent on its
/// own, without "Enregistrer" (ADR-037 §2).
struct EditProfileSheet: View {
    let store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Result<EditableProfile, EditProfileFailure>?
    @State private var profile = EditableProfile()
    /// Typed as is, French comma included; read when saving.
    @State private var weightText = ""
    @State private var error: String?
    @State private var isSaving = false
    @State private var isChoosingPhoto = false

    private var isLoaded: Bool { (try? loaded?.get()) != nil }
    private var canSave: Bool {
        isLoaded && !isSaving && ProfileName(firstName: profile.firstName, lastName: profile.lastName) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EditProfileTopBar(canSave: canSave, isSaving: isSaving, close: { dismiss() }) {
                    Task { await save() }
                }
                Divider()
                content
            }
            .background(EditProfileColors.band)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await load() }
        .avatarPicker(
            isPresented: $isChoosingPhoto,
            hasPhoto: store.profile?.athlete.avatarURL != nil,
            editor: store.avatar,
            entry: .editProfile
        )
        .presentationDetents([.large])
    }

    @ViewBuilder private var content: some View {
        switch loaded {
        case nil:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let failure):
            ContentUnavailableView {
                Label(ProfileMessages.errorTitle, systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(failure.message)
            } actions: {
                Button(ProfileMessages.retry) { Task { await load() } }
            }
        case .success:
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 0) {
                EditProfileIdentity(
                    store: store,
                    firstName: $profile.firstName,
                    lastName: $profile.lastName,
                    changePhoto: { isChoosingPhoto = true }
                )
                VStack(spacing: 0) {
                    EditProfileTextRow(placeholder: ProfileMessages.bio, text: $profile.bio, maxLength: EditableProfile.bioMaxLength, axis: .vertical)
                        .accessibilityIdentifier("editProfile.bio")
                    EditProfileTextRow(placeholder: ProfileMessages.city, text: $profile.city, maxLength: EditableProfile.cityMaxLength)
                        .textContentType(.addressCity)
                        .accessibilityIdentifier("editProfile.city")
                    EditProfileCountryRow(countryCode: $profile.countryCode)
                    EditProfileSportRow(sport: $profile.mainSport)
                }
                .background(EditProfileColors.cell)
                EditProfileSectionHeader(title: ProfileMessages.athleteInformation)
                VStack(spacing: 0) {
                    EditProfileBirthDateRow(birthDate: $profile.birthDate)
                    EditProfileGenderRow(gender: $profile.gender)
                    EditProfileWeightRow(text: $weightText)
                }
                .background(EditProfileColors.cell)
                VStack(alignment: .leading, spacing: 8) {
                    Text(ProfileMessages.weightFooter)
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.spacing)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func load() async {
        loaded = nil
        let result = await store.editableProfile()
        if case .success(let editable) = result {
            profile = editable
            weightText = editable.weightKg.map(EditProfileFormat.weight) ?? ""
        }
        loaded = result
    }

    private func save() async {
        guard let weight = EditProfileFormat.weightKg(from: weightText) else {
            error = ProfileMessages.message(for: .weight)
            return
        }
        var edited = profile
        edited.weightKg = weight ?? profile.weightKg
        isSaving = true
        defer { isSaving = false }
        error = await store.save(edited)
        if error == nil {
            dismiss()
        }
    }
}

/// The bar of the sheet: a round ✕, "Profil", and a black "Enregistrer" capsule.
private struct EditProfileTopBar: View {
    let canSave: Bool
    let isSaving: Bool
    let close: () -> Void
    let save: () -> Void

    var body: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(EditProfileColors.cell))
                    .overlay(Circle().stroke(Color(.separator).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
            .accessibilityLabel(ProfileMessages.close)
            Spacer()
            Button(action: save) {
                ZStack {
                    Text(ProfileMessages.save).opacity(isSaving ? 0 : 1)
                    if isSaving {
                        ProgressView().tint(Color(.systemBackground))
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Capsule().fill(Color.primary))
                .opacity(canSave || isSaving ? 1 : 0.35)
            }
            .disabled(!canSave)
            .accessibilityIdentifier("editProfile.save")
        }
        .overlay {
            Text(ProfileMessages.profileTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 10)
        .background(EditProfileColors.cell)
    }
}
