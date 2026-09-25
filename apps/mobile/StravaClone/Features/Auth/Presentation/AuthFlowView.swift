import SwiftUI

/// Non-authenticated flow: toggles between sign-in and sign-up (ADR-022). Wireframe:
/// no onboarding/branding screen, just the two forms.
struct AuthFlowView: View {
    enum Mode { case signIn, signUp }

    @State var store: AuthStore
    @State private var mode: Mode = .signIn

    var body: some View {
        NavigationStack {
            switch mode {
            case .signIn:
                SignInView(store: store, mode: $mode)
            case .signUp:
                SignUpView(store: store, mode: $mode)
            }
        }
    }
}

/// Shared "Continuer avec Google" button (SF Symbol placeholder, no brand logo — wireframe).
struct GoogleSignInButton: View {
    @State var store: AuthStore

    var body: some View {
        Button {
            Task { await store.signInWithGoogle() }
        } label: {
            Label("Continuer avec Google", systemImage: "g.circle")
        }
        .disabled(store.isSubmitting)
    }
}

/// Maps `AuthStore.FormError` to a displayable, non-technical message (French, ADR-022).
enum AuthFormErrorMessage {
    static func text(_ error: AuthStore.FormError) -> String {
        switch error {
        case .invalidCredentials: "Email ou mot de passe incorrect."
        case .emailAlreadyInUse: "Un compte existe déjà avec cet email."
        case .rateLimited: "Trop de tentatives, réessayez dans une minute."
        case .offline: "Pas de connexion internet."
        case .message(let message): message.isEmpty ? "Une erreur est survenue, réessayez." : message
        }
    }
}
