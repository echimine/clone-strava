import Foundation

/// « Supprimer mon compte » (ADR-038 §13): Réglages pushes a new screen each time.
extension Di {
    func makeAccountDeletionStore(
        signOutWarning: @escaping @MainActor () async -> String?,
        accountDeleted: @escaping @MainActor () async -> Void
    ) -> AccountDeletionStore {
        AccountDeletionStore(
            repository: APIAccountDeletionRepository(apiClient: apiClient),
            signOutWarning: signOutWarning,
            accountDeleted: accountDeleted
        )
    }
}
