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
                if !email.isEmpty && !isEmailValid {
                    Text("Email invalide")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                SecureField("Mot de passe", text: $password)
                    // No .textContentType(.newPassword): iOS's Strong Password
                    // suggestion silently substitutes its own generated password over
                    // what's typed here — including under XCUITest automation.
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
                .disabled(store.isSubmitting || name.isEmpty || !isEmailValid || password.isEmpty)
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

    private var isEmailValid: Bool {
        EmailValidation.isValid(email)
    }

    private var errorMessage: String? {
        store.formError.map(AuthFormErrorMessage.text)
    }
}
