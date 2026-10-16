import SwiftUI

/// An Activity's detail (ADR-033 §3), pushed in the Home tab from a processed feed card:
/// loading, error with "Réessayer", the unavailable state with "Retour", or the Activity.
struct ActivityDetailPage: View {
    @State private var store: ActivityDetailStore
    /// The comment thread (ADR-034 §6).
    @State private var comments: ActivityCommentsStore

    @Environment(\.dismiss) private var dismiss

    init(
        request: ActivityDetailRequest,
        makeStore: @MainActor (ActivityID) -> ActivityDetailStore,
        makeCommentsStore: @MainActor (ActivityDetailRequest, ActivityDetailStore) -> ActivityCommentsStore
    ) {
        let store = makeStore(request.id)
        _store = State(initialValue: store)
        _comments = State(initialValue: makeCommentsStore(request, store))
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.detail.map { ActivityFormatters.sportLabel($0.sport) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.load() }
            .toast($comments.toast)
            .accessibilityIdentifier("activityDetail")
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label(ActivityDetailMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(ActivityDetailMessages.retry) { Task { await store.retry() } }
                    .buttonStyle(.borderedProminent)
            }
        case .unavailable:
            ContentUnavailableView {
                Label(ActivityDetailMessages.unavailableTitle, systemImage: "eye.slash")
            } actions: {
                Button(ActivityDetailMessages.back) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("activityDetail.back")
            }
        case .loaded(let detail):
            ScrollViewReader { proxy in
                ActivityDetailContent(detail: detail, comments: comments)
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) { ActivityCommentComposer(store: comments) }
                    .onChange(of: comments.isComposerFocused, initial: true) { scrollToComments(proxy) }
                    .onChange(of: comments.comments.count) { scrollToComments(proxy) }
            }
        }
    }

    /// While writing, the end of the thread stays in view; from the card's comment button the
    /// detail opens on it (ADR-034 §6).
    private func scrollToComments(_ proxy: ScrollViewProxy) {
        guard comments.isComposerFocused else { return }
        withAnimation { proxy.scrollTo(ActivityCommentsSection.endAnchor, anchor: .bottom) }
    }
}

/// The loaded Activity: map, header, title and description, stats grid, then the comments.
struct ActivityDetailContent: View {
    let detail: ActivityDetail
    var comments: ActivityCommentsStore?

    private let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let route = detail.route {
                    ActivityRouteMap(route: route)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    ActivityCardHeader(post: detail.post)
                    Text(detail.title)
                        .font(.title2.weight(.bold))
                        .accessibilityIdentifier("activityDetail.title")
                    if let description = detail.description {
                        Text(description)
                            .font(.body)
                            .accessibilityIdentifier("activityDetail.description")
                    }
                    if let stats = detail.stats {
                        statsGrid(ActivityStatItem.items(for: stats, sport: detail.sport))
                    }
                    if let comments {
                        ActivityCommentsSection(store: comments)
                        Color.clear.frame(height: 1).id(ActivityCommentsSection.endAnchor)
                    }
                }
                .padding(.horizontal, Theme.spacing)
            }
            .padding(.bottom, Theme.spacing)
        }
    }

    private func statsGrid(_ items: [ActivityStatItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.spacing) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.spacing)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("activityDetail.stats")
    }
}

#if DEBUG
private struct PreviewActivityDetailRepository: ActivityDetailRepository {
    func detail(id: ActivityID) async throws(ActivityDetailError) -> ActivityDetail {
        let post = ActivityPost.preview
        return ActivityDetail(
            id: id,
            title: post.title,
            description: "Boucle autour du lac, vent de face au retour.",
            sport: post.sport,
            visibility: .public,
            startedAt: post.startedAt,
            locationName: post.locationName,
            stats: ActivityStats(
                distance: post.distance,
                movingTime: post.movingTime,
                elapsedTime: .seconds(3_400),
                elevationGain: post.elevationGain,
                avgSpeedMs: 3.27,
                maxSpeedMs: 4.6,
                avgHeartRate: 152,
                maxHeartRate: 178,
                calories: 712
            ),
            route: post.route,
            author: post.author,
            engagement: post.engagement,
            viewerIsAuthor: false
        )
    }
}

#Preview {
    NavigationStack {
        ActivityDetailPage(
            request: ActivityDetailRequest(id: ActivityID()),
            makeStore: { id in
                ActivityDetailStore(
                    id: id,
                    loadDetail: LoadActivityDetail(repository: PreviewActivityDetailRepository()),
                    changes: ActivityChanges()
                )
            },
            makeCommentsStore: { request, detail in
                .forDetail(detail, request: request, useCases: ActivityCommentUseCases(repository: PreviewActivityCommentRepository()))
            }
        )
    }
    .tint(Theme.accent)
}
#endif
