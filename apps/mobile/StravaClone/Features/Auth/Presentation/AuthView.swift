import SwiftUI

/// Shown once signed in (ADR-022): who is connected, and a way to sign out.
/// The non-authenticated flow is `AuthFlowView`, shown instead of the TabView by `RootView`.
struct AuthView: View {
    @State var store: AuthStore

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
                    Button("Se déconnecter", role: .destructive) {
                        Task { await store.signOut() }
                    }
                }
            }
            .navigationTitle("Compte")
        }
    }
}
