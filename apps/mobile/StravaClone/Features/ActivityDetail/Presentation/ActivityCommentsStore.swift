import Foundation
import Observation

/// The comment thread under an Activity's detail (ADR-034 §6).
@Observable
@MainActor
final class ActivityCommentsStore {
    /// A comment as the thread shows it.
    struct Row: Identifiable, Equatable {
        enum Status: Equatable {
            case sent
            /// Greyed, "Envoi…".
            case sending
            /// "Échec · Réessayer", the text kept.
            case failed
        }

        var comment: ActivityComment
        var status: Status

        var id: UUID { comment.id }

        /// The long-press menu: what the API lets the viewer do, once the comment is sent.
        var actions: [CommentAction] {
            guard status == .sent else { return [] }
            return (comment.viewerCanEdit ? [.edit] : []) + (comment.viewerCanDelete ? [.delete] : [])
        }
    }

    /// "Modifier" or "Supprimer" in a comment's menu.
    enum CommentAction: Hashable {
        case edit
        case delete
    }

    let activityId: ActivityID
    /// Oldest first.
    private(set) var comments: [Row] = []
    private var previousCursor: String?
    /// Nothing could be loaded: "Réessayer".
    private(set) var loadFailed = false
    /// The composer's text.
    var draft = ""
    /// The comment "Modification… ✕" is about: sending issues its `PATCH`.
    private(set) var editing: UUID?
    var isComposerFocused: Bool
    /// Asked by "Supprimer", before the `DELETE`.
    var pendingDeletion: ActivityComment?
    /// Why an edit or a delete went back.
    var toast: String?

    @ObservationIgnored private let useCases: ActivityCommentUseCases
    @ObservationIgnored private let viewer: @MainActor () -> ActivityAuthor
    @ObservationIgnored private let onCountChange: @MainActor (Int) -> Void

    /// - Parameters:
    ///   - request: from the card's comment button (`showsComments`), the composer starts focused.
    ///   - viewer: the author shown on a comment being sent.
    ///   - onCountChange: each comment the thread gains or loses (sent, deleted, rolled back).
    init(
        request: ActivityDetailRequest,
        useCases: ActivityCommentUseCases,
        viewer: @escaping @MainActor () -> ActivityAuthor,
        onCountChange: @escaping @MainActor (Int) -> Void
    ) {
        activityId = request.id
        isComposerFocused = request.showsComments
        self.useCases = useCases
        self.viewer = viewer
        self.onCountChange = onCountChange
    }

    /// The thread of `detail`'s screen: its count changes reach the detail, and from there the
    /// feed card (ADR-033 §7).
    static func forDetail(
        _ detail: ActivityDetailStore,
        request: ActivityDetailRequest,
        useCases: ActivityCommentUseCases
    ) -> ActivityCommentsStore {
        ActivityCommentsStore(
            request: request,
            useCases: useCases,
            viewer: { [weak detail] in
                // The API does not give the viewer's own identity to the detail: the Activity's
                // author is the viewer when they wrote it, otherwise "Vous" until the answer.
                guard let loaded = detail?.detail, loaded.viewerIsAuthor else {
                    return ActivityAuthor(id: "", displayName: ActivityCommentMessages.you, avatarURL: nil)
                }
                return loaded.author
            },
            onCountChange: { [weak detail] delta in detail?.commentCountChanged(by: delta) }
        )
    }

    /// "Voir les commentaires précédents".
    var hasPreviousComments: Bool { previousCursor != nil }

    /// The newest page, on each appearance and on any catch-up (realtime reconnection): the
    /// comments not sent yet stay, last.
    func load() async {
        do {
            let page = try await useCases.page(activityId)
            let unsent = comments.filter { $0.status != .sent && !page.items.map(\.id).contains($0.id) }
            comments = page.items.map { Row(comment: $0, status: .sent) } + unsent
            previousCursor = page.previousCursor
            loadFailed = false
        } catch {
            loadFailed = comments.isEmpty
        }
    }

    func loadPrevious() async {
        guard let cursor = previousCursor,
              let page = try? await useCases.page(activityId, before: cursor) else { return }
        let older = page.items.filter { !knows($0.id) }.map { Row(comment: $0, status: .sent) }
        comments.insert(contentsOf: older, at: 0)
        previousCursor = page.previousCursor
    }

    // MARK: Comments from elsewhere (ADR-034 §5: realtime `comment.*` events)

    /// Shown already, in any state: a `comment.created` about it is the echo of a send.
    func knows(_ id: UUID) -> Bool {
        index(of: id) != nil
    }

    /// A comment fetched after a `comment.created` / `comment.updated`: inserted in
    /// chronological order, or replacing the shown one. A comment still being sent or failed is
    /// left to its own `POST`.
    func receive(_ comment: ActivityComment) {
        if let index = index(of: comment.id) {
            guard comments[index].status == .sent, comments[index].comment != comment else { return }
            comments[index].comment = comment
            return
        }
        let position = comments.firstIndex { $0.status == .sent && $0.comment.createdAt > comment.createdAt }
            ?? comments.firstIndex { $0.status != .sent }
            ?? comments.endIndex
        comments.insert(Row(comment: comment, status: .sent), at: position)
        onCountChange(1)
    }

    /// A `comment.created` / `comment.updated` about a comment not known in that state: fetched,
    /// then shown; gone meanwhile (`404`), it is removed.
    func refresh(_ id: UUID) async {
        do {
            receive(try await useCases.comment(id, on: activityId))
        } catch .notFound {
            remove(id)
        } catch {
            // Missed: the next catch-up (reconnection, new appearance) brings it.
        }
    }

    /// A `comment.deleted`, or a `404` on fetching it.
    func remove(_ id: UUID) {
        guard let index = index(of: id), comments[index].status == .sent else { return }
        comments.remove(at: index)
        onCountChange(-1)
        if editing == id { cancelEditing() }
        if pendingDeletion?.id == id { pendingDeletion = nil }
    }

    /// Sends the composer's text: a new comment shows at once under its app-generated id; an
    /// edit replaces the text at once.
    func send() async {
        guard let body = ActivityComment.sendableBody(draft) else { return }
        draft = ""
        if let id = editing {
            editing = nil
            await edit(id, body: body)
            return
        }
        let comment = ActivityComment(
            id: UUID(),
            body: body,
            createdAt: .now,
            updatedAt: nil,
            author: viewer(),
            viewerCanEdit: true,
            viewerCanDelete: true
        )
        comments.append(Row(comment: comment, status: .sending))
        await post(comment)
    }

    /// "Réessayer" on a failed send: the same `POST`, same id and text.
    func retry(_ id: UUID) async {
        guard let index = index(of: id), comments[index].status == .failed else { return }
        comments[index].status = .sending
        await post(comments[index].comment)
    }

    private func post(_ comment: ActivityComment) async {
        do {
            let stored = try await useCases.add(comment.id, body: comment.body, on: activityId)
            guard let index = index(of: comment.id) else { return }
            comments[index] = Row(comment: stored, status: .sent)
            onCountChange(1)
        } catch {
            guard let index = index(of: comment.id) else { return }
            comments[index].status = .failed
        }
    }

    /// "Modifier": the text goes into the composer, under the "Modification…" banner.
    func startEditing(_ id: UUID) {
        guard let row = row(id), row.actions.contains(.edit) else { return }
        editing = id
        draft = row.comment.body
        isComposerFocused = true
    }

    /// "✕" on the banner.
    func cancelEditing() {
        editing = nil
        draft = ""
    }

    private func edit(_ id: UUID, body: String) async {
        guard let index = index(of: id), comments[index].comment.body != body else { return }
        let previous = comments[index].comment
        comments[index].comment.body = body
        comments[index].comment.updatedAt = .now
        do {
            let stored = try await useCases.edit(id, body: body, on: activityId)
            guard let index = self.index(of: id) else { return }
            comments[index].comment = stored
        } catch {
            guard let index = self.index(of: id) else { return }
            comments[index].comment = previous
            toast = ActivityCommentMessages.editFailed
        }
    }

    /// "Supprimer": asks for confirmation first.
    func requestDeletion(_ id: UUID) {
        guard let row = row(id), row.actions.contains(.delete) else { return }
        pendingDeletion = row.comment
    }

    /// The confirmation's "Supprimer": gone at once, back in place if the `DELETE` fails.
    func confirmDeletion() async {
        guard let comment = pendingDeletion else { return }
        pendingDeletion = nil
        guard let index = index(of: comment.id) else { return }
        let removed = comments.remove(at: index)
        onCountChange(-1)
        do {
            try await useCases.delete(comment.id, on: activityId)
        } catch {
            guard self.index(of: comment.id) == nil else { return }
            comments.insert(removed, at: min(index, comments.count))
            onCountChange(1)
            toast = ActivityCommentMessages.deleteFailed
        }
    }

    private func row(_ id: UUID) -> Row? {
        comments.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? {
        comments.firstIndex { $0.id == id }
    }
}
