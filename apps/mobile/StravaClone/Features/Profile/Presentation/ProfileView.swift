import SwiftUI

struct ProfileView: View {
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
