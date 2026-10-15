import SwiftUI

/// Profile tab. Knows nothing of other features (ADR-007 rule 5): the app shell passes the
/// "Mes Itinéraires" screen (ADR-030), and what a sign-out would lose (changes not sent yet,
/// ADR-030 §8): when `signOutWarning` returns a message, a confirmation shows it first.
struct ProfileView<Itineraries: View>: View {
    @State var store: AuthStore
    var signOutWarning: @MainActor () async -> String? = { nil }
    /// Run before signing out, once the warning is confirmed or when there is none: the local
    /// data is wiped (Recording, local Activities, ADR-031 §10, §14).
    var beforeSignOut: @MainActor () async -> Void = {}
    @ViewBuilder var itineraries: () -> Itineraries

    @State private var pendingSignOutWarning: String?

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
        }
    }
}
