import SwiftUI

/// Home tab: the activity feed (ADR-029). Knows nothing of other features (ADR-007 rule 5):
/// the app shell passes the "+" action, the content shown above the feed (e.g. the import
/// banner) and `openActivity`, the Activity detail pushed in this tab's stack (ADR-033 §1).
struct FeedView<TopContent: View, ActivityDestination: View>: View {
    @Bindable var store: FeedStore
    var onImportActivity: () -> Void = {}
    @ViewBuilder var openActivity: (ActivityDetailRequest) -> ActivityDestination
    @ViewBuilder var topContent: () -> TopContent

    var body: some View {
        NavigationStack(path: $store.path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .safeAreaInset(edge: .top, spacing: 8) { topContent() }
                .homeHeader(HomeHeaderActions(onImportActivity: onImportActivity))
                .task { await store.loadIfNeeded() }
                .task { await store.observeActivityChanges() }
                .task { await store.observeLocalActivities() }
                .alert(
                    store.notice ?? "",
                    isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                }
                .navigationDestination(for: ActivityDetailRequest.self) { request in
                    openActivity(request)
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading where store.posts.isEmpty && store.localCards.isEmpty:
            ProgressView()
        case .failed(let message) where store.posts.isEmpty && store.localCards.isEmpty:
            ContentUnavailableView {
                Label(FeedMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(FeedMessages.retry) { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if store.isEmpty {
                ScrollView {
                    ContentUnavailableView(
                        FeedMessages.emptyTitle,
                        systemImage: "figure.run",
                        description: Text(FeedMessages.emptyDescription)
                    )
                    .padding(.top, 80)
                }
                .refreshable { await store.pullToRefresh() }
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    Color.clear.frame(height: 0).id(Self.topID)
                    // ADR-031 §14: the Activities not yet on the server, always on top.
                    ForEach(store.localCards, id: \.rowID) { card in
                        LocalActivityCardView(
                            card: card,
                            onDelete: { Task { await store.deleteLocalActivity(card.id) } },
                            onRetry: { Task { await store.retryLocalActivity(card.id) } }
                        )
                    }
                    if case .failed(let message) = store.phase, store.posts.isEmpty {
                        Label(message, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    ForEach(store.posts) { post in
                        ActivityCard(
                            post: post,
                            onToggleKudos: { Task { await store.toggleKudos(on: post.id) } },
                            onComments: { store.open(post.id, showingComments: true) }
                        )
                        // ADR-033 §1: a tap outside the card's buttons opens the detail (the
                        // buttons keep their own action).
                        .contentShape(.rect(cornerRadius: 20))
                        .onTapGesture { store.open(post.id) }
                        .accessibilityAction(named: Text("Ouvrir l'activité")) { store.open(post.id) }
                        .task { await store.loadMoreIfNeeded(currentPost: post) }
                    }
                    if store.isLoadingMore {
                        ProgressView().padding()
                    }
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 8)
            }
            .refreshable { await store.pullToRefresh() }
            .accessibilityIdentifier("feed.list")
            .onChange(of: store.scrollToTopRequest) {
                withAnimation { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }

    private static var topID: String { "feed.top" }
}

private extension LocalActivityCard {
    /// The post the server returns for this Activity has the same UUID: under one id,
    /// `LazyVStack` kept showing this card's view in its place, stuck on "Traitement…".
    var rowID: String { "local-\(id)" }
}

extension FeedView where TopContent == EmptyView, ActivityDestination == EmptyView {
    init(store: FeedStore, onImportActivity: @escaping () -> Void = {}) {
        self.init(store: store, onImportActivity: onImportActivity, openActivity: { _ in EmptyView() }) { EmptyView() }
    }
}

#if DEBUG
private struct PreviewFeedRepository: FeedRepository {
    func page(cursor: String?) async throws(FeedError) -> FeedPage {
        FeedPage(posts: [.preview], nextCursor: nil)
    }

    func setKudos(_ given: Bool, activityId: ActivityID) async throws(FeedError) -> KudosState {
        KudosState(kudosCount: given ? 4 : 3, viewerHasKudoed: given)
    }
}

private struct PreviewFeedEvents: FeedEventSource {
    func activityChanges() async -> AsyncStream<Void> { AsyncStream { _ in } }
}

#Preview {
    let repository = PreviewFeedRepository()
    FeedView(
        store: FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: PreviewFeedEvents()
        )
    )
    .tint(Theme.accent)
}
#endif
