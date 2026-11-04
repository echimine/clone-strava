import Foundation
import Observation

/// « Supprimer mon compte » (ADR-038 §13): a confirmation listing what will be erased, the
/// sign-out warning lines and, with an App Store subscription, Apple's billing; then a Sign-in
/// code sent to the account's e-mail; then the deletion, immediate and final. Online only. Once
/// deleted, the app shell does the local sign-out cleanup and shows the Welcome.
@MainActor
@Observable
final class AccountDeletionStore {
    enum Step: Equatable {
        /// What will be erased, and « Recevoir un code ».
        case confirm
        /// The code sent, waiting to be typed.
        case code
    }

    private(set) var step = Step.confirm
    /// The `SignOutWarning` lines: what this phone has not sent yet and will lose.
    private(set) var signOutWarning: String?
    /// An App Store subscription keeps renewing: warned, never blocking.
    private(set) var appStoreBilled = false
    private(set) var isWorking = false
    private(set) var error: String?
    var code = ""

    @ObservationIgnored private let repository: any AccountDeletionRepository
    @ObservationIgnored private let warning: @MainActor () async -> String?
    @ObservationIgnored private let accountDeleted: @MainActor () async -> Void

    init(
        repository: any AccountDeletionRepository,
        signOutWarning: @escaping @MainActor () async -> String?,
        accountDeleted: @escaping @MainActor () async -> Void
    ) {
        self.repository = repository
        self.warning = signOutWarning
        self.accountDeleted = accountDeleted
    }

    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Six digits typed.
    var canConfirm: Bool {
        !isWorking && trimmedCode.count == 6 && trimmedCode.allSatisfy(\.isASCII) && trimmedCode.allSatisfy(\.isNumber)
    }

    func load() async {
        signOutWarning = await warning()
        appStoreBilled = (try? await repository.appStoreBilled()) ?? false
    }

    /// « Recevoir un code », and « Recevoir un nouveau code ».
    func sendCode() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.sendCode()
            error = nil
            code = ""
            step = .code
        } catch {
            self.error = AccountDeletionMessages.message(for: error)
        }
    }

    /// « Supprimer définitivement ».
    func confirm() async {
        guard canConfirm else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.deleteAccount(code: trimmedCode)
            error = nil
        } catch {
            self.error = AccountDeletionMessages.message(for: error)
            return
        }
        await accountDeleted()
    }
}
