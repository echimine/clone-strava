import SwiftUI

/// The account screen (ADR-035 §1, §2), one screen for both entries, only the title changes:
/// "Continuer avec Google", or an email that receives a Sign-in code (`SignInCodeView`). There
/// is no password and no Apple button.
struct AccountView: View {
    enum Mode {
        case createAccount, signIn
    }

    let mode: Mode
    /// The email step's back chevron, to the screen that opened this one (the Welcome).
    var onBack: (() -> Void)?
    @State private var store: SignInStore

    /// `name` is passed to the account if the code creates it (filled by the Onboarding). In
    /// `createAccount` mode, the sign-in ends the Onboarding: its answers are sent (ADR-035 §5).
    init(mode: Mode, authStore: AuthStore, name: String? = nil, onBack: (() -> Void)? = nil) {
        self.mode = mode
        self.onBack = onBack
        let entry: SignInEntry = mode == .createAccount ? .onboarding(name: name ?? "") : .signIn
        _store = State(initialValue: authStore.makeSignInStore(entry: entry))
    }

    var body: some View {
        Group {
            switch store.step {
            case .email:
                AccountEmailStep(mode: mode, store: store, onBack: onBack)
                    .transition(.move(edge: .leading))
            case .code(let email):
                SignInCodeView(email: email, store: store)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy, value: store.step)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

private struct AccountEmailStep: View {
    let mode: AccountView.Mode
    @Bindable var store: SignInStore
    let onBack: (() -> Void)?

    @FocusState private var isEmailFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(mode == .createAccount ? "Créer un compte" : "Se connecter")
                    .font(.system(size: 30, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                googleButton
                    .padding(.top, 32)
                separator
                    .padding(.vertical, 24)
                emailField
                continueButton
                    .padding(.top, 16)

                if let error = store.formError {
                    AuthMessage(text: error.text)
                        .padding(.top, 12)
                }
                if mode == .createAccount {
                    Text("Déjà inscrit ? Utilisez la même adresse ou le même compte Google : vous serez connecté.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { legalFooter }
        .overlay(alignment: .topLeading) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.secondarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(store.isSendingCode || store.isSigningInWithGoogle)
                .accessibilityLabel("Retour")
                .accessibilityIdentifier("account.back")
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
    }

    private var subtitle: String {
        switch mode {
        case .createAccount: "Pour enregistrer vos réponses et retrouver vos activités sur tous vos appareils."
        case .signIn: "Content de vous revoir. Aucun mot de passe : nous vous envoyons un code."
        }
    }

    private var googleButton: some View {
        Button {
            Task { await store.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                if store.isSigningInWithGoogle {
                    ProgressView()
                } else {
                    Image("GoogleLogo")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text("Continuer avec Google")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .overlay(Capsule().strokeBorder(Color(.separator)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!store.canUseGoogle)
        .opacity(store.canUseGoogle ? 1 : 0.45)
        .accessibilityIdentifier("account.google")
    }

    private var separator: some View {
        HStack(spacing: 12) {
            line
            Text("ou").font(.subheadline).foregroundStyle(.secondary)
            line
        }
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle().fill(Color(.separator)).frame(height: 1)
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email")
                .font(.subheadline.weight(.semibold))
            TextField("vous@exemple.fr", text: $store.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.continue)
                .focused($isEmailFocused)
                .onSubmit { Task { await store.sendCode() } }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator)))
                .disabled(store.isSendingCode)
                .accessibilityLabel("Email")
                .accessibilityIdentifier("account.email")
        }
    }

    private var continueButton: some View {
        Button {
            Task { await store.sendCode() }
        } label: {
            ZStack {
                if store.isSendingCode {
                    ProgressView().tint(.white)
                } else {
                    Text("Continuer")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!store.canSendCode)
        .accessibilityLabel(store.isSendingCode ? "Envoi du code en cours" : "Continuer")
        .accessibilityIdentifier("account.continue")
    }

    private var legalFooter: some View {
        VStack(spacing: 4) {
            Text("En continuant, vous acceptez les Conditions d'utilisation et la Politique de confidentialité de Nervo.")
                .multilineTextAlignment(.center)
            LegalLinks()
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }
}

/// An error line under a field or the code boxes.
struct AuthMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
#Preview("Se connecter") {
    AccountView(mode: .signIn, authStore: .preview)
}

#Preview("Créer un compte") {
    AccountView(mode: .createAccount, authStore: .preview)
}
#endif
