import SwiftUI

/// The Commentaires segment of the Kudos and comments screen (ADR-034 §6, ADR-036 §8): "Voir les
/// commentaires précédents", then the comments oldest first. A long press offers "Modifier" /
/// "Supprimer", and "Signaler" on other athletes' comments (ADR-038 §9).
struct ActivityCommentsSection: View {
    @Bindable var store: ActivityCommentsStore

    /// Scroll id of the end of the thread, placed by the screen under this section.
    static let endAnchor = "activityComments.end"

    @Environment(\.reportContent) private var reportContent

    private func report(_ row: ActivityCommentsStore.Row) {
        let author = row.comment.author
        reportContent?(.comment(row.id.uuidString.lowercased(), by: author)) { [store] hiding in
            switch hiding {
            case .target: store.hide(row.id)
            case .author: store.hideComments(of: author.id)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .commentAccessibilityActions(row.actions,
                        edit: { store.startEditing(row.id) },
                        delete: { store.requestDeletion(row.id) })
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
                        // ADR-038 §9: others' comments, also for the Activity's author.
                        if reportContent != nil, row.isReportable {
                            Button(ModerationLabels.report, systemImage: ModerationLabels.reportImage) {
                                report(row)
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

private extension View {
    /// The context menu's "Modifier" / "Supprimer" as VoiceOver actions, only those the viewer has.
    @ViewBuilder
    func commentAccessibilityActions(
        _ actions: [ActivityCommentsStore.CommentAction],
        edit: @escaping () -> Void,
        delete: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            accessibilityActions {
                if actions.contains(.edit) { Button(ActivityCommentMessages.edit, action: edit) }
                if actions.contains(.delete) { Button(ActivityCommentMessages.delete, action: delete) }
            }
        } else {
            accessibilityAction(named: ActivityCommentMessages.edit) { if actions.contains(.edit) { edit() } }
                .accessibilityAction(named: ActivityCommentMessages.delete) { if actions.contains(.delete) { delete() } }
        }
    }
}

/// One comment: avatar and name (both open the author's profile, ADR-036 §8), time with "modifié", text; greyed with "Envoi…"
/// while sent, "Échec · Réessayer" when the send failed.
struct ActivityCommentRow: View {
    let row: ActivityCommentsStore.Row
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AthleteButton(athlete: row.comment.author) {
                AvatarView(name: row.comment.author.displayName, url: row.comment.author.avatarURL, size: 32)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    AthleteButton(athlete: row.comment.author) {
                        Text(row.comment.author.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .accessibilityIdentifier("activityComments.author")
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

/// The composer pinned to the bottom of the Kudos and comments screen, with the "Modification… ✕" banner while a
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
