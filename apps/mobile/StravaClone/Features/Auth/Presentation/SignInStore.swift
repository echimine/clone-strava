import Foundation
import Observation

/// The account screen and its Sign-in code screen (ADR-035 §1, §2): Google, or an email that
/// receives a 6-digit code. Made by `AuthStore.makeSignInStore(entry:)`, which it signs in.
@Observable
@MainActor
final class SignInStore {
    enum Step: Equatable {
        case email
        /// The code was sent to `email`.
        case code(email: String)
    }

    var email = ""
    private(set) var step = Step.email
    private(set) var isSendingCode = false
    /// What the code boxes show.
    private(set) var code = ""
    private(set) var isVerifyingCode = false
    private(set) var isSigningInWithGoogle = false
    private(set) var codeProblem: CodeProblem?

    enum CodeProblem: Equatable {
        /// "Code incorrect.": the boxes were cleared for another try.
        case wrong
        /// Expired, or its 3 attempts are spent: only a new code helps.
        case noLongerValid
    }

    var canSendCode: Bool {
        EmailValidation.isValid(trimmedEmail) && !isBusy
    }

    var canUseGoogle: Bool { !isBusy }

    var isCodeEntryDisabled: Bool { codeProblem == .noLongerValid }

    /// What could not be done, other than a code refused (`codeProblem`).
    private(set) var formError: FormError?

    /// Seconds before "Recevoir un nouveau code" opens (30 after each code sent, ADR-035 §2).
    private(set) var resendCountdown = 0

    /// "Recevoir un nouveau code".
    var canResendCode: Bool {
        guard case .code = step else { return false }
        return resendCountdown == 0 && !isBusy
    }

    @ObservationIgnored private var failedAttempts = 0
    @ObservationIgnored private var countdown: Task<Void, Never>?

    @ObservationIgnored private let service: AuthService
    @ObservationIgnored private let name: String?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let onSignedIn: @MainActor (AuthUser) -> Void

    init(
        service: AuthService,
        name: String?,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        onSignedIn: @escaping @MainActor (AuthUser) -> Void
    ) {
        self.service = service
        self.name = name
        self.sleep = sleep
        self.onSignedIn = onSignedIn
    }

    /// "Continuer" on the account screen.
    func sendCode() async {
        guard case .email = step, canSendCode else { return }
        await requestCode(for: trimmedEmail)
    }

    /// "Recevoir un nouveau code": the previous code is replaced by a new one (`rotate`).
    func resendCode() async {
        guard case .code(let email) = step, canResendCode else { return }
        await requestCode(for: email)
    }

    /// "Continuer avec Google". Closing Google's sheet is a no-op, not an error to show.
    func signInWithGoogle() async {
        guard canUseGoogle else { return }
        isSigningInWithGoogle = true
        formError = nil
        defer { isSigningInWithGoogle = false }
        do throws(AuthError) {
            onSignedIn(try await service.signInWithGoogle())
        } catch .googleSignInCancelled {
        } catch {
            formError = FormError(error)
        }
    }

    /// The code screen's back chevron: back to the address, to correct it.
    func editEmail() {
        guard case .code = step, !isBusy else { return }
        step = .email
        resetCode()
        stopCountdown()
    }

    private func requestCode(for email: String) async {
        isSendingCode = true
        formError = nil
        defer { isSendingCode = false }
        do throws(AuthError) {
            try await service.sendSignInCode(email: email)
            step = .code(email: email)
            resetCode()
            startCountdown()
        } catch {
            formError = FormError(error)
        }
    }

    private func resetCode() {
        code = ""
        codeProblem = nil
        failedAttempts = 0
    }

    private func startCountdown() {
        countdown?.cancel()
        resendCountdown = Self.resendDelaySeconds
        countdown = Task { [weak self, sleep] in
            while let self, self.resendCountdown > 0 {
                do { try await sleep(.seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                self.resendCountdown -= 1
            }
        }
    }

    private func stopCountdown() {
        countdown?.cancel()
        countdown = nil
        resendCountdown = 0
    }

    /// The code boxes' text field: keeps the digits only (a pasted "123 456" too), at most 6.
    /// The 6th digit submits the code.
    func enterCode(_ text: String) {
        guard case .code(let email) = step, !isCodeEntryDisabled, !isVerifyingCode else { return }
        code = String(text.filter { $0.isASCII && $0.isNumber }.prefix(Self.codeLength))
        if !code.isEmpty {
            formError = nil
            if codeProblem == .wrong { codeProblem = nil }
        }
        guard code.count == Self.codeLength else { return }
        let code = code
        isVerifyingCode = true
        Task {
            defer { isVerifyingCode = false }
            do throws(AuthError) {
                onSignedIn(try await service.signIn(email: email, code: code, name: name))
            } catch {
                codeRejected(error)
            }
        }
    }

    static let codeLength = 6
    /// The server's attempts per code (Better Auth emailOTP's default `allowedAttempts`).
    static let attemptsPerCode = 3
    /// In step with the server's 3 sends per minute and per IP.
    static let resendDelaySeconds = 30

    private func codeRejected(_ error: AuthError) {
        code = ""
        switch error {
        case .invalidCode:
            failedAttempts += 1
            // The 3rd wrong code still gets `INVALID_OTP`, but the code is spent.
            if failedAttempts >= Self.attemptsPerCode {
                codeNoLongerValid()
            } else {
                codeProblem = .wrong
            }
        case .codeExpired, .tooManyAttempts:
            codeNoLongerValid()
        default:
            formError = FormError(error)
        }
    }

    /// The boxes are disabled and the resend opens right away, as the main button.
    private func codeNoLongerValid() {
        codeProblem = .noLongerValid
        stopCountdown()
    }

    private var isBusy: Bool { isSendingCode || isVerifyingCode || isSigningInWithGoogle }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
