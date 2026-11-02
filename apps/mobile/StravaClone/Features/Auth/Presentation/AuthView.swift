import SwiftUI

/// Shown once signed in (ADR-022): who is connected, and a way to sign out.
/// Signed out, `RootView` shows the account screen (`AccountView`) instead of the TabView.
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
