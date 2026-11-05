import SwiftUI

/// The Kudos and comments screen (ADR-036 §8), pushed from the detail's kudos row and comment
/// button, and from the card's comment button: a segmented Kudos · N / Commentaires · N, the
/// givers page by page, or the comment thread with its composer pinned to the bottom. Loading,
/// error and unavailable states are the detail's.
struct ActivityEngagementPage: View {
    @State private var store: ActivityEngagementStore
    /// Kept live while shown (ADR-034 §5).
    private let liveEvents: any ActivityLiveEventSource

    @Environment(\.dismiss) private var dismiss

    init(
        request: ActivityEngagementRequest,
        makeStore: @MainActor (ActivityEngagementRequest) -> ActivityEngagementStore,
        liveEvents: any ActivityLiveEventSource
    ) {
        _store = State(initialValue: makeStore(request))
        self.liveEvents = liveEvents
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.detail.detail?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.load() }
            .task { await store.detail.observeEvents() }
            // Subscribed while shown, unsubscribed when the task ends with the screen.
            .task { await ActivityLiveUpdates(events: liveEvents, engagement: store).run() }
            .toast(Bindable(store.comments).toast)
            .accessibilityIdentifier("activityEngagement")
    }

    @ViewBuilder private var content: some View {
        switch store.detail.phase {
        case .loading:
            ProgressView()
                .accessibilityLabel("Chargement")
        case .failed(let message):
            ContentUnavailableView {
                Label(ActivityDetailMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(ActivityDetailMessages.retry) { Task { await store.detail.retry() } }
                    .buttonStyle(.borderedProminent)
            }
        case .unavailable:
            ContentUnavailableView {
                Label(ActivityDetailMessages.unavailableTitle, systemImage: "eye.slash")
            } actions: {
                Button(ActivityDetailMessages.back) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("activityEngagement.back")
            }
        case .loaded:
            VStack(spacing: 0) {
                Picker(ActivityEngagementMessages.tabs, selection: $store.tab) {
                    Text(store.kudosTitle).tag(ActivityEngagementStore.Tab.kudos)
                    Text(store.commentsTitle).tag(ActivityEngagementStore.Tab.comments)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 8)
                .accessibilityIdentifier("activityEngagement.tabs")

                switch store.tab {
                case .kudos:
                    KudosListView(store: store.kudos)
                        // ADR-037 §1: an expired pre-signed Avatar URL brings fresh ones.
                        .onImageURLExpired { await store.kudos.load() }
                case .comments:
                    ActivityEngagementComments(store: store.comments)
                        .onImageURLExpired { await store.comments.load() }
                }
            }
        }
    }
}

/// The Commentaires segment: the thread, newest at the bottom, over the pinned composer.
private struct ActivityEngagementComments: View {
    @Bindable var store: ActivityCommentsStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ActivityCommentsSection(store: store)
                    Color.clear.frame(height: 1).id(ActivityCommentsSection.endAnchor)
                }
                .padding(Theme.spacing)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { ActivityCommentComposer(store: store) }
            .onChange(of: store.isComposerFocused, initial: true) { scrollToEnd(proxy) }
            .onChange(of: store.comments.count) { scrollToEnd(proxy) }
        }
    }

    /// While writing, the end of the thread stays in view (ADR-034 §6).
    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard store.isComposerFocused else { return }
        withAnimation { proxy.scrollTo(ActivityCommentsSection.endAnchor, anchor: .bottom) }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ActivityEngagementPage(
            request: .comments(ActivityID()),
            makeStore: { request in
                let detail = ActivityDetailStore.preview(id: request.activityId)
                let repository = PreviewActivityCommentRepository()
                return ActivityEngagementStore(
                    request: request,
                    detail: detail,
                    comments: .forDetail(
                        detail,
                        request: request,
                        loadComments: LoadActivityComments(repository: repository),
                        loadComment: LoadActivityComment(repository: repository),
                        addComment: AddActivityComment(repository: repository),
                        editComment: EditActivityComment(repository: repository),
                        deleteComment: DeleteActivityComment(repository: repository)
                    )
                )
            },
            liveEvents: PreviewActivityLiveEventSource()
        )
    }
    .tint(Theme.accent)
}
#endif
