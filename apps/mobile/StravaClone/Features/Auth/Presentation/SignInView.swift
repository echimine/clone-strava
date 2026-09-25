import SwiftUI

/// Wireframe: system components only, no custom styling beyond Theme.accent.
struct SignInView: View {
    @State var store: AuthStore
    @Binding var mode: AuthFlowView.Mode

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("signIn.email")
                if !email.isEmpty && !isEmailValid {
                    Text("Email invalide")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                SecureField("Mot de passe", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("signIn.password")
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
                    Task { await store.signIn(email: email, password: password) }
                } label: {
                    HStack {
                        Text("Se connecter")
                        if store.isSubmitting { Spacer(); ProgressView() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(store.isSubmitting || !isEmailValid || password.isEmpty)
                .accessibilityIdentifier("signIn.submit")

                GoogleSignInButton(store: store)
            }

            Section {
                Button("Pas de compte ? Créer un compte") { mode = .signUp }
                    .disabled(store.isSubmitting)
            }
        }
        .navigationTitle("Connexion")
    }

    private var isEmailValid: Bool {
        EmailValidation.isValid(email)
    }

    private var errorMessage: String? {
        store.formError.map(AuthFormErrorMessage.text)
    }
}
