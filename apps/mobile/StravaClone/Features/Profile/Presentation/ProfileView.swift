import SwiftUI

/// Profile tab. Knows nothing of other features (ADR-007 rule 5): the app shell passes the
/// "Mes Itinéraires" screen (ADR-030), and what a sign-out would lose (changes not sent yet,
/// ADR-030 §8): when `signOutWarning` returns a message, a confirmation shows it first.
/// Its "Confidentialité" section holds the Measurement consent switch and the legal texts
/// (ADR-035 §8, §9).
struct ProfileView<Itineraries: View>: View {
    @State var store: AuthStore
    let consent: MeasurementConsentStore
    var signOutWarning: @MainActor () async -> String? = { nil }
    /// Run before signing out, once the warning is confirmed or when there is none: the local
    /// data is wiped (Recording, local Activities, ADR-031 §10, §14).
    var beforeSignOut: @MainActor () async -> Void = {}
    /// Debug builds only: the app shell passes its animations preview screen.
    var animationsPreview: AnyView?
    @ViewBuilder var itineraries: () -> Itineraries

    @State private var pendingSignOutWarning: String?
    @State private var openedDocument: LegalDocument?

    var body: some View {
        NavigationStack {
            Form {
                if case .signedIn(let user) = store.state {
                    Section {
                        LabeledContent("Nom", value: user.name)
                        LabeledContent("Email", value: user.email)
                    }
                }
                Section {
                    NavigationLink {
                        itineraries()
                    } label: {
                        Label("Mes Itinéraires", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
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
                                await store.signOut()
                            }
                        }
                    }
                    .accessibilityIdentifier("signOut")
                }
            }
            .navigationTitle("Compte")
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
                        await store.signOut()
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: { warning in
                Text(warning)
            }
            .sheet(item: $openedDocument) { LegalSheet(document: $0) }
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Mesure d'audience", isOn: Binding(
                get: { consent.isMeasurementEnabled },
                set: { enabled in Task { await consent.setMeasurementEnabled(enabled) } }
            ))
            .accessibilityIdentifier("privacy.measurement")
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
            Text("Écrans vus et boutons touchés, jamais votre nom, votre email ni vos activités.")
        }
    }
}
