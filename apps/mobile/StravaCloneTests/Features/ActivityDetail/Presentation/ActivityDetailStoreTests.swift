import Foundation
import Testing
@testable import StravaClone

/// The Activity detail (ADR-033 §3): loading, error with retry, and the unavailable state
/// when the Activity is gone or no longer visible.
@MainActor
struct ActivityDetailStoreTests {
    private func makeStore(
        _ repository: FakeActivityDetailRepository,
        id: ActivityID,
        changes: ActivityChanges = ActivityChanges()
    ) -> ActivityDetailStore {
        let kudos = FakeActivityKudosRepository()
        return ActivityDetailStore(
            id: id,
            loadDetail: LoadActivityDetail(repository: repository),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: changes
        )
    }

    @Test func loadingShowsTheActivity() async {
        let detail = ActivityDetail.fixture()
        let repository = FakeActivityDetailRepository(.success(detail))
        let store = makeStore(repository, id: detail.id)
        #expect(store.phase == .loading)

        await store.load()

        #expect(store.phase == .loaded(detail))
        #expect(repository.requestedIds == [detail.id])
    }

    @Test func anErrorOffersARetryThatShowsTheActivity() async {
        let detail = ActivityDetail.fixture()
        let repository = FakeActivityDetailRepository(.failure(.offline), .success(detail))
        let store = makeStore(repository, id: detail.id)

        await store.load()
        #expect(store.phase == .failed(message: "Vous êtes hors ligne."))

        await store.retry()
        #expect(store.phase == .loaded(detail))
    }

    @Test func aNotFoundShowsTheUnavailableState() async {
        let id = ActivityID()
        let store = makeStore(FakeActivityDetailRepository(.failure(.notFound)), id: id)

        await store.load()

        #expect(store.phase == .unavailable)
    }

    /// A reload that fails keeps what is shown: the screen never loses a loaded Activity to a
    /// network error.
    @Test func aFailedReloadKeepsTheLoadedActivity() async {
        let detail = ActivityDetail.fixture()
        let store = makeStore(FakeActivityDetailRepository(.success(detail), .failure(.network)), id: detail.id)
        await store.load()

        await store.load()

        #expect(store.phase == .loaded(detail))
    }

    /// The feed follows the detail (ADR-033 §7): what the detail loads replaces the card, and a
    /// `404` removes it. A failure tells nothing.
    @Test func whatTheDetailLearnsIsPublishedForTheFeed() async {
        let detail = ActivityDetail.fixture(title: "Renommée")
        let changes = ActivityChanges()
        let published = changes.subscribe()
        let gone = ActivityID()
        let marker = ActivityChange.deleted(ActivityID())

        await makeStore(FakeActivityDetailRepository(.success(detail)), id: detail.id, changes: changes).load()
        await makeStore(FakeActivityDetailRepository(.failure(.notFound)), id: gone, changes: changes).load()
        await makeStore(FakeActivityDetailRepository(.failure(.network)), id: ActivityID(), changes: changes).load()
        changes.publish(marker)

        var received: [ActivityChange] = []
        for await change in published {
            received.append(change)
            if change == marker { break }
        }
        #expect(received == [.updated(detail.post), .deleted(gone), marker])
    }
}
