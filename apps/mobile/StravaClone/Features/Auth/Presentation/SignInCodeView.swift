import SwiftUI

/// The Sign-in code screen (ADR-035 §2): 6 boxes filled from Mail's suggestion
/// (`.oneTimeCode`), submitted at the 6th digit, "Recevoir un nouveau code" after 30 s,
/// "Ouvrir Mail", and a chevron back to the address.
struct SignInCodeView: View {
    let email: String
    @Bindable var store: SignInStore

    @FocusState private var isCodeFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton
            Text("Nous vous avons envoyé un code")
                .font(.system(size: 30, weight: .bold))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)
            Text("Saisissez le code à 6 chiffres envoyé à **\(email)**")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            SignInCodeBoxes(
                code: store.code,
                problem: store.codeProblem,
                isFocused: isCodeFocused && !store.isCodeEntryDisabled
            )
            .overlay { codeField }
            .padding(.top, 28)

            messages
            resend

            Spacer(minLength: 24)
            openMailButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .onAppear { isCodeFocused = true }
    }

    private var backButton: some View {
        Button {
            store.editEmail()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.secondarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modifier l'adresse email")
        .accessibilityIdentifier("signInCode.back")
    }

    /// The text field behind the boxes: it holds the keyboard, Mail's suggestion and the
    /// paste menu, while the boxes only draw its digits.
    private var codeField: some View {
        TextField("", text: Binding(get: { store.code }, set: { store.enterCode($0) }))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($isCodeFocused)
            // Not disabled while a code is checked (the store ignores typing then): a disabled
            // field loses the keyboard, which a wrong code must keep.
            .disabled(store.isCodeEntryDisabled)
            .onChange(of: store.isCodeEntryDisabled) { _, disabled in
                if !disabled { isCodeFocused = true }
            }
            .foregroundStyle(.clear)
            .tint(.clear)
            .accessibilityLabel("Code à 6 chiffres")
            .accessibilityValue(store.code)
            .accessibilityIdentifier("signInCode.field")
    }

    @ViewBuilder private var messages: some View {
        if store.isVerifyingCode {
            ProgressView()
                .padding(.top, 12)
        }
        if store.codeProblem == .wrong {
            AuthMessage(text: "Code incorrect.")
                .padding(.top, 12)
        }
        if store.codeProblem == .noLongerValid {
            Label {
                Text("**Ce code n'est plus valable.** Demandez-en un nouveau.")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
            .padding(.top, 16)
        }
        if let error = store.formError {
            AuthMessage(text: error.text)
                .padding(.top, 12)
        }
    }

    /// The main button once the code is no longer valid, else a small one with its countdown.
    @ViewBuilder private var resend: some View {
        let button = Button {
            Task { await store.resendCode() }
        } label: {
            ZStack {
                if store.isSendingCode {
                    ProgressView()
                } else {
                    Text("Recevoir un nouveau code")
                }
            }
        }
        .disabled(!store.canResendCode)
        .accessibilityIdentifier("signInCode.resend")

        if store.codeProblem == .noLongerValid {
            button
                .buttonStyle(AuthPrimaryButtonStyle())
                .padding(.top, 20)
        } else {
            HStack(spacing: 12) {
                button
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Color(.secondarySystemFill)))
                    .buttonStyle(.plain)
                    .foregroundStyle(store.canResendCode ? Theme.accent : .secondary)
                if store.resendCountdown > 0 {
                    Text("Possible dans \(Self.countdown(store.resendCountdown))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.top, 18)
        }
    }

    private var openMailButton: some View {
        Button {
            if let mail = URL(string: "message://") { openURL(mail) }
        } label: {
            Label("Ouvrir Mail", systemImage: "envelope")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    /// "0:24".
    static func countdown(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The 6 boxes: the typed digits, a caret in the next box, red after a wrong code, grey once
/// the code is no longer valid.
private struct SignInCodeBoxes: View {
    let code: String
    let problem: SignInStore.CodeProblem?
    let isFocused: Bool

    var body: some View {
        let digits = Array(code)
        HStack(spacing: 8) {
            ForEach(0 ..< SignInStore.codeLength, id: \.self) { index in
                box(digit: index < digits.count ? String(digits[index]) : nil, isCurrent: index == digits.count)
            }
        }
        .accessibilityHidden(true)
    }

    private func box(digit: String?, isCurrent: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let active = isCurrent && isFocused
        return ZStack {
            shape.fill(fill)
            shape.strokeBorder(border(active: active), lineWidth: active ? 2 : 1)
            if let digit {
                Text(digit).font(.title.weight(.semibold))
            } else if active {
                Rectangle().fill(border(active: true)).frame(width: 2, height: 26)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
    }

    private var fill: Color {
        switch problem {
        case .wrong: Color.red.opacity(0.05)
        case .noLongerValid: Color(.secondarySystemFill)
        case nil: Color(.systemBackground)
        }
    }

    private func border(active: Bool) -> Color {
        switch problem {
        case .wrong: .red
        case .noLongerValid: Color(.separator)
        case nil: active ? Theme.accent : Color(.separator)
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var store = AuthStore.preview.makeSignInStore()
    SignInCodeView(email: "camille.martin@gmail.com", store: store)
        .task {
            store.email = "camille.martin@gmail.com"
            await store.sendCode()
        }
}
#endif
