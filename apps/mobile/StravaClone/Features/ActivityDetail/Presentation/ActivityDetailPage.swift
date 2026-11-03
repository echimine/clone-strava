import SwiftUI

/// An Activity's detail (ADR-033 §3), pushed in the Home tab from a processed feed card:
/// loading, error with "Réessayer", the unavailable state with "Retour", or the Activity.
struct ActivityDetailPage: View {
    @State private var store: ActivityDetailStore
    /// Kept live while shown (ADR-034 §5).
    private let liveEvents: any ActivityLiveEventSource
    /// "⋯" > "Supprimer", waiting for its confirmation.
    @State private var deletionCandidate: ActivityID?

    @Environment(\.dismiss) private var dismiss

    init(
        request: ActivityDetailRequest,
        makeStore: @MainActor (ActivityID) -> ActivityDetailStore,
        liveEvents: any ActivityLiveEventSource
    ) {
        _store = State(initialValue: makeStore(request.id))
        self.liveEvents = liveEvents
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.detail.map { ActivityFormatters.sportLabel($0.sport) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { manageMenu }
            .activityEditing(store.editor)
            // ADR-033 §7: back to the feed at once, where the card is already gone.
            .activityDeleteConfirmation($deletionCandidate) { _ in
                Task { await store.delete() }
                dismiss()
            }
            // Also on coming back from the Kudos and comments screen: the counts changed there.
            .task { await store.load() }
            .task { await store.observeEvents() }
            // Subscribed while shown, unsubscribed when the task ends with the screen.
            .task { await ActivityLiveUpdates(events: liveEvents, detail: store).run() }
            .toast($store.kudosNotice)
            .accessibilityIdentifier("activityDetail")
    }

    /// "⋯" for the author only (ADR-033 §3).
    @ToolbarContentBuilder private var manageMenu: some ToolbarContent {
        if let detail = store.detail, detail.viewerIsAuthor {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ActivityManageButtons(
                        onEdit: { store.editor.edit(detail) },
                        onDelete: { deletionCandidate = detail.id }
                    )
                } label: {
                    Label(ActivityDetailMessages.manage, systemImage: "ellipsis")
                }
                .accessibilityIdentifier("activityDetail.manage")
            }
        }
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
            ActivityDetailContent(detail: detail) {
                ActivityKudosSection(store: store, engagement: detail.engagement)
            }
        }
    }
}

/// The loaded Activity: map, header, title and description, stats grid, then the kudos and
/// comments block under the stats (ADR-036 §8).
struct ActivityDetailContent<Engagement: View>: View {
    let detail: ActivityDetail
    @ViewBuilder let engagement: () -> Engagement

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
                    engagement()
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
            source: .recorded,
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
            routeTrimmed: true,
            analysis: .preview,
            author: post.author,
            engagement: post.engagement,
            viewerIsAuthor: true
        )
    }

    func update(id: ActivityID, with edit: ActivityEdit) async throws(ActivityDetailError) -> ActivityDetail {
        edit.applied(to: try await detail(id: id))
    }

    func delete(id: ActivityID) async throws(ActivityDetailError) {}
}

extension ActivityAnalysis {
    /// 10,14 km with a climb, heart rate on, for previews.
    static var preview: ActivityAnalysis {
        let paces: [Double] = [298, 305, 312, 296, 289, 318, 330, 301, 293, 285, 280]
        let splits = paces.enumerated().map { index, secondsPerKm in
            let meters = index == paces.count - 1 ? 140.0 : 1_000
            return ActivitySplit(
                distance: Distance(meters: meters),
                movingTime: .seconds(Int((secondsPerKm * meters / 1_000).rounded())),
                elevationDiff: [4, 12, -3, 8, -10, 22, 18, -15, -20, -6, 1][index],
                avgHeartRate: 140 + index * 3
            )
        }
        let samples = 200
        let distances = (0..<samples).map { Double($0) * 10_140 / Double(samples - 1) }
        return ActivityAnalysis(
            splits: splits,
            series: ActivitySeries(
                distanceM: distances,
                speedMs: distances.map { 3.3 + 0.3 * sin($0 / 900) + ($0 > 6_000 && $0 < 6_100 ? -3.3 : 0) },
                altitudeM: distances.map { 450 + 35 * sin($0 / 2_500) },
                heartRateBpm: distances.map { 138 + Int(25 * $0 / 10_140) }
            )
        )
    }
}

private struct PreviewActivityKudosRepository: ActivityKudosRepository {
    func kudos(activityId: ActivityID, cursor: String?, limit: Int) async throws(ActivityDetailError) -> KudosPage {
        let names = ["Léo Bernard", "Inès Petit", "Hugo Moreau", "Chloé Laurent", "Lucas Simon", "Emma Roux"]
        let givers = names.enumerated().map { index, name in
            KudosGiver(athlete: ActivityAuthor(id: "\(index)", displayName: name, avatarURL: nil), givenAt: .now)
        }
        return KudosPage(givers: Array(givers.prefix(limit)), nextCursor: nil)
    }

    func setKudos(_ given: Bool, activityId: ActivityID) async throws(ActivityDetailError) -> KudosState {
        KudosState(kudosCount: given ? 7 : 6, viewerHasKudoed: given)
    }
}

/// No live event, for previews.
struct PreviewActivityLiveEventSource: ActivityLiveEventSource {
    func events(of activityId: ActivityID) -> AsyncStream<ActivityLiveEvent> {
        AsyncStream { _ in }
    }
}

extension ActivityDetailStore {
    /// An Activity of the athlete, with 6 kudos, for previews.
    static func preview(id: ActivityID) -> ActivityDetailStore {
        let changes = ActivityChanges()
        return ActivityDetailStore(
            id: id,
            loadDetail: LoadActivityDetail(repository: PreviewActivityDetailRepository()),
            loadKudos: LoadKudosList(repository: PreviewActivityKudosRepository()),
            setKudos: SetActivityKudos(repository: PreviewActivityKudosRepository()),
            changes: changes,
            updateActivity: UpdateActivity(repository: PreviewActivityDetailRepository()),
            deleter: ActivityDeleter(
                deleteActivity: DeleteActivity(repository: PreviewActivityDetailRepository()),
                changes: changes
            )
        )
    }
}

#Preview {
    NavigationStack {
        ActivityDetailPage(
            request: ActivityDetailRequest(id: ActivityID()),
            makeStore: { id in .preview(id: id) },
            liveEvents: PreviewActivityLiveEventSource()
        )
    }
    .tint(Theme.accent)
}
#endif
