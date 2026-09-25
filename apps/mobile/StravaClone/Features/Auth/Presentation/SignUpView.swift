import SwiftUI

/// Wireframe: system components only, no custom styling beyond Theme.accent.
struct SignUpView: View {
    @State var store: AuthStore
    @Binding var mode: AuthFlowView.Mode

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                TextField("Nom", text: $name)
                    .textContentType(.name)
                    .accessibilityIdentifier("signUp.name")
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("signUp.email")
                SecureField("Mot de passe", text: $password)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("signUp.password")
            }

            if let message = errorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await store.signUp(email: email, password: password, name: name) }
                } label: {
                    HStack {
                        Text("Créer un compte")
                        if store.isSubmitting { Spacer(); ProgressView() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(store.isSubmitting || name.isEmpty || email.isEmpty || password.isEmpty)
                .accessibilityIdentifier("signUp.submit")

                GoogleSignInButton(store: store)
            }

            Section {
                Button("Déjà un compte ? Se connecter") { mode = .signIn }
                    .disabled(store.isSubmitting)
            }
        }
        .navigationTitle("Créer un compte")
    }

    private var errorMessage: String? {
        store.formError.map(AuthFormErrorMessage.text)
    }
}
