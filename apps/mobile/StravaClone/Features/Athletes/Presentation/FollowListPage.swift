import SwiftUI

/// An athlete's followers and following lists (ADR-036 §1, §10), pushed in the current tab's
/// stack from their counters: "Abonnés · N" / "Abonnements · N", paged, a follow button on each
/// row. On my own followers: "Demandes d'abonnement" at the top while someone asks, and a
/// swipe to remove a follower, once confirmed. A tap on an athlete opens their profile through
/// `\.openAthlete`.
struct FollowListPage: View {
    @State private var store: FollowListStore
    @State private var removalCandidate: AthleteListItem?
    @State private var showsRequests = false

    init(request: AthleteFollowsRequest, makeStore: @MainActor (AthleteFollowsRequest) -> FollowListStore) {
        _store = State(initialValue: makeStore(request))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: Binding(get: { store.selected }, set: { list in
                store.selected = list
                Task { await store.show(list) }
            })) {
                ForEach(AthleteFollowsRequest.Kind.allCases, id: \.self) { list in
                    Text(AthletesMessages.listTitle(list, count: count(of: list))).tag(list)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 8)
            .accessibilityIdentifier("followList.tabs")
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .navigationTitle(store.athleteName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .navigationDestination(isPresented: $showsRequests) {
            FollowRequestsView(store: store.requests)
        }
        .confirmationDialog(
            removalCandidate.map { AthletesMessages.removeFollowerTitle($0.athlete.displayName) } ?? "",
            isPresented: Binding(get: { removalCandidate != nil }, set: { if !$0 { removalCandidate = nil } }),
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { item in
            Button(AthletesMessages.remove, role: .destructive) {
                Task { await store.removeFollower(item.id) }
            }
        } message: { _ in
            Text(AthletesMessages.removeFollowerMessage)
        }
        .toast(Binding(get: { store.toast }, set: { store.toast = $0 }))
        .toast(Binding(get: { store.follows.toast }, set: { store.follows.toast = $0 }))
        .accessibilityIdentifier("followList")
    }

    private func count(of list: AthleteFollowsRequest.Kind) -> Int {
        list == .followers ? store.followerCount : store.followingCount
    }

    @ViewBuilder private var content: some View {
        let list = store.selected
        switch store.phase(of: list) {
        case .idle, .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label(AthletesMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(AthletesMessages.retry) { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            rows(list)
        }
    }

    private func rows(_ list: AthleteFollowsRequest.Kind) -> some View {
        List {
            if store.showsRequestsRow {
                requestsRow
            }
            ForEach(store.items(of: list)) { item in
                AthleteRow(athlete: item.athlete) {
                    FollowButton.row(athleteId: item.id, store: store.follows)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if list == .followers, store.canRemoveFollowers {
                        Button(AthletesMessages.remove) { removalCandidate = item }
                            .tint(.red)
                    }
                }
                .task { await store.loadMoreIfNeeded(current: item) }
            }
            if store.isLoadingMore(list) {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .refreshable { await store.refresh() }
        .overlay {
            if store.items(of: list).isEmpty, !store.showsRequestsRow {
                ContentUnavailableView(
                    list == .followers ? AthletesMessages.emptyFollowersTitle : AthletesMessages.emptyFollowingTitle,
                    systemImage: "person.2"
                )
            }
        }
    }

    private var requestsRow: some View {
        Button {
            showsRequests = true
        } label: {
            HStack {
                Image(systemName: "person.badge.clock")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AthletesMessages.followRequests)
                        .font(.body.weight(.semibold))
                    Text(AthletesMessages.pendingRequests(store.pendingRequestCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("followList.requests")
    }
}

/// "Demandes d'abonnement" (ADR-036 §1): Accepter or Refuser each request.
struct FollowRequestsView: View {
    let store: FollowRequestsStore

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle(AthletesMessages.followRequests)
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.load() }
            .toast(Binding(get: { store.toast }, set: { store.toast = $0 }))
            .accessibilityIdentifier("followRequests")
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle:
            ProgressView()
        case .loading where store.items.isEmpty:
            ProgressView()
        case .failed(let message) where store.items.isEmpty:
            ContentUnavailableView {
                Label(AthletesMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(AthletesMessages.retry) { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            List {
                ForEach(store.items) { request in
                    AthleteRow(athlete: request.athlete) {
                        HStack(spacing: 8) {
                            Button(AthletesMessages.accept) { Task { await store.accept(request.id) } }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)
                                .accessibilityIdentifier("followRequests.accept")
                            Button(AthletesMessages.refuse) { Task { await store.refuse(request.id) } }
                                .buttonStyle(.bordered)
                                .tint(.secondary)
                                .accessibilityIdentifier("followRequests.refuse")
                        }
                        .controlSize(.small)
                        .fontWeight(.semibold)
                    }
                    .task { await store.loadMoreIfNeeded(current: request) }
                }
            }
            .listStyle(.plain)
            .refreshable { await store.refresh() }
            .overlay {
                if store.isEmpty {
                    ContentUnavailableView(
                        AthletesMessages.emptyRequestsTitle,
                        systemImage: "person.badge.clock",
                        description: Text(AthletesMessages.emptyRequestsDescription)
                    )
                }
            }
        }
    }
}
