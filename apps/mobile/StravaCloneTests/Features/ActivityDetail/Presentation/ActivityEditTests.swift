import Foundation
import Testing
@testable import StravaClone

/// Editing an Activity (ADR-033 §7): online and optimistic. The sheet closes and the detail and
/// the feed card change at once; a failure brings the previous values back with a toast, and a
/// `422` reopens the sheet with the athlete's input.
@MainActor
struct ActivityEditTests {
    private let previous = ActivityDetail.fixture(title: "Sortie du matin", sport: .run)

    private var renamed: ActivityDetail {
        var detail = previous
        detail.title = "Sortie vélo"
        detail.description = "Avec Paul"
        detail.sport = .ride
        detail.visibility = .followers
        return detail
    }

    /// The feed showing the card of `previous`, following `changes`.
    private func makeFeed(changes: ActivityChanges) async -> FeedStore {
        let repository = FakeFeedRepository()
        repository.pages[nil] = .success(FeedPage(posts: [previous.post], nextCursor: nil))
        let feed = FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: FakeFeedEventSource(),
            activityChanges: changes
        )
        await feed.refresh()
        return feed
    }

    private func makeDetail(_ repository: FakeActivityDetailRepository, changes: ActivityChanges) async -> ActivityDetailStore {
        let store = ActivityDetailStore(
            id: previous.id,
            loadDetail: LoadActivityDetail(repository: repository),
            updateActivity: UpdateActivity(repository: repository),
            changes: changes
        )
        await store.load()
        return store
    }

    /// The sheet filled with `renamed`'s values.
    private func editedForm(_ editor: ActivityEditor) throws -> ActivityEditor.Form {
        var form = try #require(editor.form)
        form.title = "  Sortie vélo "
        form.description = "Avec Paul"
        form.sport = .ride
        form.visibility = .followers
        return form
    }

    private static func first(_ count: Int, of stream: AsyncStream<ActivityChange>) async -> [ActivityChange] {
        var received: [ActivityChange] = []
        for await change in stream {
            received.append(change)
            if received.count == count { break }
        }
        return received
    }

    @Test func aSuccessfulEditShowsAtOnceInTheDetailAndTheCard() async throws {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(previous))
        let (gate, release) = AsyncStream<Void>.makeStream()
        repository.updateGate = gate
        repository.updateResult = .success(renamed)
        let store = await makeDetail(repository, changes: changes)

        store.editor.edit(previous)
        let form = try editedForm(store.editor)
        #expect(store.editor.form?.title == "Sortie du matin")
        let saving = Task { await store.editor.save(form) }

        // Before the server answers: the sheet is closed, the detail and the card are edited.
        #expect(await eventually { repository.updates.count == 1 })
        #expect(store.editor.form == nil)
        #expect(store.detail == renamed)
        #expect(await eventually { feed.posts == [renamed.post] })
        #expect(repository.updates.first?.edit == ActivityEdit(
            title: "Sortie vélo", description: "Avec Paul", sport: .ride, visibility: .followers
        ))

        release.yield()
        await saving.value
        #expect(store.detail == renamed)
        #expect(feed.posts == [renamed.post])
        #expect(store.editor.toast == nil)
    }

    @Test func aFailedEditBringsThePreviousValuesBackWithAToast() async throws {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(previous))
        repository.updateResult = .failure(.network)
        let store = await makeDetail(repository, changes: changes)
        store.editor.edit(previous)
        let published = changes.subscribe()

        await store.editor.save(try editedForm(store.editor))

        #expect(repository.updates.count == 1)
        #expect(store.detail == previous)
        // The card took the new values, then the previous ones again.
        #expect(await Self.first(2, of: published) == [.updated(renamed.post), .updated(previous.post)])
        #expect(await eventually { feed.posts == [previous.post] })
        #expect(store.editor.form == nil)
        #expect(store.editor.toast == "La modification n'a pas pu être enregistrée.")
    }

    /// `422` (ADR-033 §7): the values go back and the sheet reopens with what the athlete typed
    /// and the server's reason.
    @Test func aRefusedEditReopensTheSheetWithTheAthletesInput() async throws {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(previous))
        repository.updateResult = .failure(.invalid(code: "activity_too_short_for_sport"))
        let store = await makeDetail(repository, changes: changes)
        store.editor.edit(previous)
        let submitted = try editedForm(store.editor)
        let published = changes.subscribe()

        await store.editor.save(submitted)

        #expect(store.detail == previous)
        #expect(await Self.first(2, of: published) == [.updated(renamed.post), .updated(previous.post)])
        #expect(await eventually { feed.posts == [previous.post] })
        var reopened = submitted
        reopened.errorMessage = "Cette activité est trop courte pour ce sport."
        #expect(store.editor.form == reopened)
        #expect(store.editor.toast == nil)
    }

    @Test func saveIsDisabledWhileTheTitleIsBlank() throws {
        var form = ActivityEditor.Form(detail: previous)
        #expect(form.canSave)
        form.title = "   "
        #expect(!form.canSave)
    }

    /// An emptied description is cleared on the server (ADR-033 §4).
    @Test func anEmptiedDescriptionIsCleared() {
        var form = ActivityEditor.Form(detail: ActivityDetail.fixture(description: "Belle boucle"))
        form.description = "  "
        #expect(form.edit.description == nil)
    }

    /// From a feed card's context menu (ADR-033 §1): no detail is open, the sheet opens once the
    /// Activity is read, and the save reaches the card.
    @Test func anEditFromTheFeedCardUpdatesTheCard() async throws {
        let changes = ActivityChanges()
        let feed = await makeFeed(changes: changes)
        let repository = FakeActivityDetailRepository(.success(previous))
        repository.updateResult = .success(renamed)
        let editor = ActivityEditor(
            loadDetail: LoadActivityDetail(repository: repository),
            updateActivity: UpdateActivity(repository: repository),
            changes: changes
        )

        await editor.edit(id: previous.id)
        #expect(editor.form == ActivityEditor.Form(detail: previous))
        await editor.save(try editedForm(editor))

        #expect(await eventually { feed.posts == [renamed.post] })
    }

    @Test func aCardWhoseActivityCannotBeReadShowsAToast() async {
        let editor = ActivityEditor(
            loadDetail: LoadActivityDetail(repository: FakeActivityDetailRepository(.failure(.offline))),
            updateActivity: UpdateActivity(repository: FakeActivityDetailRepository()),
            changes: ActivityChanges()
        )

        await editor.edit(id: previous.id)

        #expect(editor.form == nil)
        #expect(editor.toast == "Vous êtes hors ligne.")
    }
}
