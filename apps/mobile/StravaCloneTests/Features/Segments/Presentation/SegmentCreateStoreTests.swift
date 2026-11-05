import Foundation
import Testing
@testable import StravaClone

/// The preview screen (ADR-039 §15): the name with its counter, « Créer le Segment », and the
/// refusals shown there (duplicate with a link, quota).
@MainActor
struct SegmentCreateStoreTests {
    private let path = [Coordinate(latitude: 45.9, longitude: 6.12), Coordinate(latitude: 45.909, longitude: 6.12)]

    private func makeStore(
        repository: FakeSegmentCreationRepository = FakeSegmentCreationRepository(),
        preview: SegmentPreview? = nil,
        isOnline: @escaping @MainActor () -> Bool = { true }
    ) -> SegmentCreateStore {
        SegmentCreateStore(
            candidate: SegmentCandidate(sport: .ride, points: path, preview: preview ?? FakeSegmentCreationRepository.preview(of: path)),
            repository: repository,
            isOnline: isOnline
        )
    }

    @Test func countsTheTrimmedNameFrom3To60Characters() {
        let store = makeStore()
        #expect(!store.canCreate)
        #expect(store.nameHint == nil)

        store.name = "  ab  "
        #expect(store.counterText == "2/60")
        #expect(store.nameHint == "3 caractères au moins.")
        #expect(!store.canCreate)

        store.name = " Col du Semnoz "
        #expect(store.counterText == "13/60")
        #expect(store.nameHint == nil)
        #expect(store.canCreate)

        store.name = String(repeating: "a", count: 61)
        #expect(store.nameHint == "60 caractères au plus.")
        #expect(!store.canCreate)
    }

    @Test func createsTheSegmentWithTheTrimmedNameAndTheDrawnPath() async {
        let repository = FakeSegmentCreationRepository()
        await repository.answerCreation(with: .success(SegmentRef(id: "seg-9", name: "Col du Semnoz")))
        let store = makeStore(repository: repository)
        store.name = "  Col du Semnoz "

        await store.create()

        #expect(await repository.creations == [.init(sport: .ride, name: "Col du Semnoz", points: path)])
        #expect(store.created == SegmentRef(id: "seg-9", name: "Col du Semnoz"))
    }

    @Test func showsTheDuplicateThePreviewFoundAndDoesNotOfferToCreate() {
        let existing = SegmentRef(id: "seg-2", name: "Le Semnoz")
        let store = makeStore(preview: FakeSegmentCreationRepository.preview(of: path, duplicate: existing))
        store.name = "Mon Semnoz"

        #expect(store.duplicate == existing)
        #expect(!store.canCreate)
    }

    @Test func showsADuplicateTheServerFoundOnCreation() async {
        let repository = FakeSegmentCreationRepository()
        let existing = SegmentRef(id: "seg-3", name: "Le Semnoz")
        await repository.answerCreation(with: .failure(.duplicate(existing)))
        let store = makeStore(repository: repository)
        store.name = "Mon Semnoz"

        await store.create()

        #expect(store.created == nil)
        #expect(store.duplicate == existing)
    }

    @Test func showsTheQuotaFromThePreviewOrTheServer() async {
        let fromPreview = makeStore(preview: FakeSegmentCreationRepository.preview(of: path, quotaLeft: 0))
        fromPreview.name = "Col du Semnoz"
        #expect(fromPreview.message == "Tu as créé 10 Segments ces dernières 24 h. Réessaie un peu plus tard.")
        #expect(!fromPreview.canCreate)

        let repository = FakeSegmentCreationRepository()
        await repository.answerCreation(with: .failure(.quotaReached))
        let fromServer = makeStore(repository: repository)
        fromServer.name = "Col du Semnoz"
        await fromServer.create()
        #expect(fromServer.message == "Tu as créé 10 Segments ces dernières 24 h. Réessaie un peu plus tard.")
    }

    @Test func offlineTheButtonSaysConnectionRequired() async {
        let repository = FakeSegmentCreationRepository()
        let store = makeStore(repository: repository, isOnline: { false })
        store.name = "Col du Semnoz"
        #expect(store.canCreate)

        await store.create()

        #expect(store.message == "Connexion requise")
        #expect(await repository.creations.isEmpty)
    }

    @Test func aFailureCanBeRetried() async {
        let repository = FakeSegmentCreationRepository()
        await repository.answerCreation(with: .failure(.unavailable))
        let store = makeStore(repository: repository)
        store.name = "Col du Semnoz"

        await store.create()
        #expect(store.message == "Le Segment n'a pas pu être créé. Réessaie.")
        #expect(store.canCreate)

        await repository.answerCreation(with: .success(SegmentRef(id: "seg-4", name: "Col du Semnoz")))
        await store.create()
        #expect(store.created?.id == "seg-4")
    }
}
