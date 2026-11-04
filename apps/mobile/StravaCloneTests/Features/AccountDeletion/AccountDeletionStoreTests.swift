import Testing
@testable import StravaClone

/// « Supprimer mon compte » (ADR-038 §13): the confirmation screen, the Sign-in code, the
/// deletion and what follows.
@MainActor
struct AccountDeletionStoreTests {
    private final class Deletions {
        var count = 0
    }

    private func makeStore(
        repository: FakeAccountDeletionRepository = FakeAccountDeletionRepository(),
        warning: String? = nil,
        deletions: Deletions = Deletions()
    ) -> AccountDeletionStore {
        AccountDeletionStore(
            repository: repository,
            signOutWarning: { warning },
            accountDeleted: { deletions.count += 1 }
        )
    }

    @Test func theConfirmationRepeatsTheSignOutLinesAndWarnsOfApplesBilling() async {
        let repository = FakeAccountDeletionRepository()
        repository.previewResult = .success(true)
        let store = makeStore(repository: repository, warning: "L'enregistrement en cours sera supprimé.")

        await store.load()

        #expect(store.signOutWarning == "L'enregistrement en cours sera supprimé.")
        #expect(store.appStoreBilled)
        #expect(store.step == .confirm)
    }

    @Test func withoutTheBillingAnswerThereIsNoPremiumWarningAndNothingBlocks() async {
        let repository = FakeAccountDeletionRepository()
        repository.previewResult = .failure(.offline)
        let store = makeStore(repository: repository)

        await store.load()

        #expect(!store.appStoreBilled)
        #expect(store.signOutWarning == nil)
    }

    @Test func askingForTheCodeSendsItThenAsksForIt() async {
        let repository = FakeAccountDeletionRepository()
        let store = makeStore(repository: repository)

        await store.sendCode()

        #expect(repository.calls == [.sendCode])
        #expect(store.step == .code)
        #expect(store.error == nil)
    }

    @Test func anAdministratorIsToldTheyCannotDeleteTheirAccount() async {
        let repository = FakeAccountDeletionRepository()
        repository.sendCodeResult = .failure(.administrator)
        let store = makeStore(repository: repository)

        await store.sendCode()

        #expect(store.step == .confirm)
        #expect(store.error == "Un administrateur ne peut pas supprimer son compte")
    }

    @Test func aWrongCodeKeepsTheAccountAndSaysSo() async {
        let repository = FakeAccountDeletionRepository()
        repository.deleteResult = .failure(.invalidCode)
        let deletions = Deletions()
        let store = makeStore(repository: repository, deletions: deletions)
        await store.sendCode()
        store.code = "123456"

        await store.confirm()

        #expect(repository.calls == [.sendCode, .delete(code: "123456")])
        #expect(store.error == AccountDeletionMessages.invalidCode)
        #expect(deletions.count == 0)
    }

    @Test func confirmIsOnlyPossibleWithASixDigitCode() async {
        let store = makeStore()
        await store.sendCode()
        store.code = "12 34"
        #expect(!store.canConfirm)
        store.code = " 123456 "
        #expect(store.canConfirm)
    }

    @Test func theRightCodeDeletesTheAccountThenHandsOverToTheAppShell() async {
        let repository = FakeAccountDeletionRepository()
        let deletions = Deletions()
        let store = makeStore(repository: repository, deletions: deletions)
        await store.sendCode()
        store.code = " 000000 "

        await store.confirm()

        #expect(repository.calls == [.sendCode, .delete(code: "000000")])
        #expect(deletions.count == 1)
        #expect(store.error == nil)
    }

    @Test func offlineTheDeletionIsNotPossible() async {
        let repository = FakeAccountDeletionRepository()
        repository.sendCodeResult = .failure(.offline)
        let store = makeStore(repository: repository)

        await store.sendCode()

        #expect(store.error == AccountDeletionMessages.offline)
    }
}
