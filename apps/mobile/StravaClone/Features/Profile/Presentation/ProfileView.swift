import SwiftUI

/// Profile tab. Knows nothing of other features (ADR-007 rule 5): the app shell passes the
/// "Mes Itinéraires" screen (ADR-030).
struct ProfileView<Itineraries: View>: View {
    @State var store: AuthStore
    @ViewBuilder var itineraries: () -> Itineraries

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
                        Task { await store.signOut() }
                    }
                }
            }
            .navigationTitle("Compte")
        }
    }
}
