import SwiftUI

/// The comment thread under the kudos block (ADR-034 §6): "Voir les commentaires précédents",
/// then the comments oldest first. A long press offers "Modifier" / "Supprimer".
struct ActivityCommentsSection: View {
    @Bindable var store: ActivityCommentsStore

    /// Scroll id of the end of the thread, placed by the detail under this section.
    static let endAnchor = "activityComments.end"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ActivityCommentMessages.title)
                .font(.headline)
            if store.hasPreviousComments {
                Button(ActivityCommentMessages.previous) { Task { await store.loadPrevious() } }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("activityComments.previous")
            }
            if store.loadFailed {
                HStack {
                    Text(ActivityCommentMessages.loadFailed)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(ActivityCommentMessages.retry) { Task { await store.load() } }
                        .font(.subheadline.weight(.semibold))
                }
            }
            ForEach(store.comments) { row in
                ActivityCommentRow(row: row) { Task { await store.retry(row.id) } }
                    .contextMenu {
                        ForEach(row.actions, id: \.self) { action in
                            switch action {
                            case .edit:
                                Button(ActivityCommentMessages.edit, systemImage: "pencil") { store.startEditing(row.id) }
                            case .delete:
                                Button(ActivityCommentMessages.delete, systemImage: "trash", role: .destructive) {
                                    store.requestDeletion(row.id)
                                }
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await store.load() }
        .confirmationDialog(
            ActivityCommentMessages.deleteConfirmation,
            isPresented: Binding(
                get: { store.pendingDeletion != nil },
                set: { if !$0 { store.pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ActivityCommentMessages.delete, role: .destructive) { Task { await store.confirmDeletion() } }
            Button(ActivityCommentMessages.cancel, role: .cancel) { store.pendingDeletion = nil }
        }
        .accessibilityIdentifier("activityComments")
    }
}

/// One comment: avatar, name (not tappable), time with "modifié", text; greyed with "Envoi…"
/// while sent, "Échec · Réessayer" when the send failed.
struct ActivityCommentRow: View {
    let row: ActivityCommentsStore.Row
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(name: row.comment.author.displayName, url: row.comment.author.avatarURL, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.comment.author.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(row.comment.body)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                switch row.status {
                case .sent:
                    EmptyView()
                case .sending:
                    Text(ActivityCommentMessages.sending)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed:
                    Button(ActivityCommentMessages.failed, action: onRetry)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("activityComments.retry")
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(row.status == .sending ? 0.5 : 1)
        .contentShape(.rect)
    }

    private var subtitle: String {
        let time = ActivityFormatters.relativeDateTime(row.comment.createdAt)
        return row.comment.updatedAt == nil ? time : "\(time) · \(ActivityCommentMessages.edited)"
    }
}

/// The composer pinned to the bottom of the detail, with the "Modification… ✕" banner while a
/// comment is being edited.
struct ActivityCommentComposer: View {
    @Bindable var store: ActivityCommentsStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.editing != nil {
                HStack {
                    Text(ActivityCommentMessages.editing)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(ActivityCommentMessages.cancelEditing, systemImage: "xmark") { store.cancelEditing() }
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("activityComments.cancelEditing")
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(ActivityCommentMessages.placeholder, text: $store.draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                    .accessibilityIdentifier("activityComments.composer")
                Button(ActivityCommentMessages.send, systemImage: "arrow.up.circle.fill") {
                    Task { await store.send() }
                }
                .labelStyle(.iconOnly)
                .font(.title)
                .disabled(ActivityComment.sendableBody(store.draft) == nil)
                .accessibilityIdentifier("activityComments.send")
            }
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: store.isComposerFocused) { _, isFocused in focused = isFocused }
        .onChange(of: focused) { _, isFocused in store.isComposerFocused = isFocused }
        .task {
            // Opened from the card's comment button: the keyboard once the push has settled.
            guard store.isComposerFocused else { return }
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
    }
}

#if DEBUG
/// Comments for previews: one comment by someone else; sending fails, to show the retry.
struct PreviewActivityCommentRepository: ActivityCommentRepository {
    private static let comment = ActivityComment(
        id: UUID(),
        body: "Belle sortie, quel rythme !",
        createdAt: .now.addingTimeInterval(-3_600),
        updatedAt: nil,
        author: ActivityAuthor(id: "u2", displayName: "Léa Durand", avatarURL: nil),
        viewerCanEdit: false,
        viewerCanDelete: true
    )

    func comments(activityId: ActivityID, before: String?) async throws(ActivityCommentError) -> ActivityCommentsPage {
        ActivityCommentsPage(items: [Self.comment], previousCursor: nil)
    }

    func comment(activityId: ActivityID, id: UUID) async throws(ActivityCommentError) -> ActivityComment {
        Self.comment
    }

    func add(activityId: ActivityID, id: UUID, body: String) async throws(ActivityCommentError) -> ActivityComment {
        throw .offline
    }

    func edit(activityId: ActivityID, id: UUID, body: String) async throws(ActivityCommentError) -> ActivityComment {
        throw .offline
    }

    func delete(activityId: ActivityID, id: UUID) async throws(ActivityCommentError) {}
}
#endif
