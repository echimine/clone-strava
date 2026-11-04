import SwiftUI

/// Réglages (ADR-036 §10), pushed by the profile's gear; it takes over the former "Compte"
/// form (ADR-035 §8): Compte (Nom opens "Modifier le profil", Email), Mes Itinéraires,
/// Confidentialité ("Approuver mes abonnés", legal texts), Debug, and
/// sign-out. When `signOutWarning` returns a message, a confirmation shows it first
/// (ADR-030 §8). The account and the sign-out come from the app shell (ADR-007 rule 5).
struct SettingsView: View {
    let store: ProfileStore
    let account: ProfileAccount?
    let signOut: @MainActor () async -> Void
    var signOutWarning: @MainActor () async -> String? = { nil }
    /// Run before signing out, once the warning is confirmed or when there is none: the local
    /// data is wiped (Recording, local Activities, ADR-031 §10, §14).
    var beforeSignOut: @MainActor () async -> Void = {}
    /// Debug builds only: the app shell passes its animations preview screen.
    var animationsPreview: AnyView?

    @State private var pendingSignOutWarning: String?
    @State private var openedDocument: LegalDocument?
    @State private var isEditingName = false

    private var displayName: String {
        store.profile?.athlete.displayName ?? account?.name ?? ""
    }

    var body: some View {
        Form {
            if let account {
                Section("Compte") {
                    Button {
                        isEditingName = true
                    } label: {
                        LabeledContent("Nom", value: displayName)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("settings.name")
                    LabeledContent("Email", value: account.email)
                }
            }
            Section {
                NavigationLink(value: ProfileStore.Destination.itineraries) {
                    Label(ProfileMessages.myItineraries, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .accessibilityIdentifier("myItinerariesLink")
            }
            privacySection
            if let animationsPreview {
                Section("Debug") {
                    NavigationLink {
                        animationsPreview
                    } label: {
                        Label("Prévisualiser les animations", systemImage: "play.rectangle")
                    }
                }
            }
            Section {
                Button("Se déconnecter", role: .destructive) {
                    Task {
                        if let warning = await signOutWarning() {
                            pendingSignOutWarning = warning
                        } else {
                            await beforeSignOut()
                            await signOut()
                        }
                    }
                }
                .accessibilityIdentifier("signOut")
            }
        }
        .navigationTitle(ProfileMessages.settings)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Se déconnecter ?",
            isPresented: Binding(
                get: { pendingSignOutWarning != nil },
                set: { if !$0 { pendingSignOutWarning = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingSignOutWarning
        ) { _ in
            Button("Se déconnecter", role: .destructive) {
                Task {
                    await beforeSignOut()
                    await signOut()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: { warning in
            Text(warning)
        }
        .sheet(item: $openedDocument) { LegalSheet(document: $0) }
        .sheet(isPresented: $isEditingName) {
            EditProfileSheet(store: store)
        }
    }

    private var privacySection: some View {
        Section {
            // Only once the profile is loaded: the switch shows the server's value (ADR-036 §1).
            if store.profile != nil {
                Toggle(ProfileMessages.approveFollowers, isOn: Binding(
                    get: { store.approveFollowers },
                    set: { approve in Task { await store.setApproveFollowers(approve) } }
                ))
                .accessibilityIdentifier("privacy.approveFollowers")
            }
            ForEach(LegalDocument.allCases) { document in
                Button {
                    openedDocument = document
                } label: {
                    LabeledContent(document.title) {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("privacy.\(document.rawValue)")
            }
        } header: {
            Text("Confidentialité")
        } footer: {
            Text(ProfileMessages.approveFollowersFooter)
        }
    }
}
