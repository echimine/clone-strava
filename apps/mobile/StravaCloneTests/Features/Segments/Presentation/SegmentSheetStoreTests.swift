import Foundation
import Testing
@testable import StravaClone

/// The Segment sheet (ADR-039 §15) through `SegmentSheetStore`: loading, a deleted Segment, the
/// star, and the creator's « Renommer » and « Supprimer ».
@MainActor
struct SegmentSheetStoreTests {
    private let repository = FakeSegmentRepository()
    private let analytics = FakeAnalyticsClient()

    private func makeStore(onDeleted: @escaping @MainActor () -> Void = {}) -> SegmentSheetStore {
        SegmentSheetStore(segmentID: "seg-1", repository: repository, analytics: analytics, onDeleted: onDeleted)
    }

    @Test func loadsTheSheet() async {
        let store = makeStore()

        await store.load()

        #expect(store.phase == .loaded(.sample()))
        #expect(repository.calls == [.sheet("seg-1")])
    }

    @Test func aDeletedSegmentIsNoLongerAvailable() async {
        repository.sheetResult = .failure(.notFound)
        let store = makeStore()

        await store.load()

        #expect(store.phase == .gone)
        #expect(SegmentMessages.gone == "Ce Segment n'est plus disponible")
    }

    @Test func aFailedLoadKeepsTheSheetShownAndSaysSo() async {
        let store = makeStore()
        await store.load()
        repository.sheetResult = .failure(.offline)

        await store.load()

        #expect(store.phase == .loaded(.sample()))
        #expect(store.toast == "Connexion requise")
    }

    @Test func theStarCountsMeAtOnceAndComesBackOnFailure() async {
        let store = makeStore()
        await store.load()

        await store.toggleStar()
        #expect(store.sheet?.isStarred == true)
        #expect(store.sheet?.favoriteCount == 4)
        #expect(repository.calls.last == .setStarred("seg-1", true))
        #expect(analytics.events == [.segmentFavorited])

        repository.starResult = .failure(.network)
        await store.toggleStar()
        #expect(store.sheet?.isStarred == true)
        #expect(store.sheet?.favoriteCount == 4)
        #expect(store.toast != nil)
    }

    @Test func supprimerIsExplainedWhenSomeoneElseHasAnEffort() async {
        repository.sheetResult = .success(.sample(isMine: true, canDelete: false))
        let store = makeStore()
        await store.load()

        store.requestDelete()

        #expect(store.deletion == .refused)
        #expect(!repository.calls.contains(.delete("seg-1")))
    }

    @Test func supprimerAfterConfirmationDeletesAndLeaves() async {
        repository.sheetResult = .success(.sample(isMine: true, canDelete: true))
        var left = false
        let store = makeStore { left = true }
        await store.load()

        store.requestDelete()
        #expect(store.deletion == .confirming)
        await store.confirmDelete()

        #expect(repository.calls.last == .delete("seg-1"))
        #expect(left)
    }

    @Test func aDeletionRefusedByTheServerIsExplained() async {
        repository.sheetResult = .success(.sample(isMine: true, canDelete: true))
        repository.deleteResult = .failure(.hasOtherEfforts)
        var left = false
        let store = makeStore { left = true }
        await store.load()

        store.requestDelete()
        await store.confirmDelete()

        #expect(store.deletion == .refused)
        #expect(!left)
    }

    @Test func renommerRenamesTheSheet() async {
        repository.sheetResult = .success(.sample(isMine: true))
        let store = makeStore()
        await store.load()

        await store.rename(to: "  Nouveau nom  ")

        #expect(repository.calls.last == .rename("seg-1", "Nouveau nom"))
        #expect(store.sheet?.name == "Nouveau nom")
    }
}
