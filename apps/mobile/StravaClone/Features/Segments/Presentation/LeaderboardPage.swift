import SwiftUI

/// A Segment's Leaderboard screen (ADR-039 §15, variant C of the prototype #238): chips in one
/// scrolling row (Tous / Hommes / Femmes, then one other filter), the Local Legend of the sex
/// chip on top, the lines, my line pinned under the top 10, and without Premium the locks and
/// the insert, each opening the Paywall in a sheet.
struct LeaderboardPage: View {
    @State private var store: LeaderboardStore
    let segmentName: String
    private let paywall: @MainActor (AnalyticsEvent.PaywallEntry, @escaping @MainActor () -> Void) -> AnyView

    init(
        segmentName: String,
        makeStore: @MainActor () -> LeaderboardStore,
        paywall: @escaping @MainActor (AnalyticsEvent.PaywallEntry, @escaping @MainActor () -> Void) -> AnyView
    ) {
        _store = State(initialValue: makeStore())
        self.segmentName = segmentName
        self.paywall = paywall
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let leaderboard = store.leaderboard {
                    LocalLegendCard(legend: leaderboard.localLegend, viewerID: leaderboard.me?.athlete.id, showsMine: false)
                        .padding(12)
                        .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 12))
                    if leaderboard.me == nil {
                        Text(SegmentMessages.notInFilter)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("leaderboard.notInFilter")
                    }
                    LeaderboardRows(
                        leaderboard: leaderboard,
                        showsPremiumInsert: true,
                        onPremiumInsert: store.tapPremiumInsert,
                        onLastAppeared: { Task { await store.loadMore() } }
                    )
                } else if store.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(Theme.spacing)
        }
        .safeAreaInset(edge: .top, spacing: 0) { chips.background(.bar) }
        .refreshable { await store.reload() }
        .navigationTitle(SegmentMessages.leaderboard)
        .navigationBarTitleDisplayMode(.inline)
        .toast($store.toast)
        .task { await store.appeared() }
        .sheet(item: $store.paywall, onDismiss: { Task { await store.reload() } }) { request in
            paywall(request.entry) { store.paywallClosed() }
        }
        .accessibilityIdentifier("leaderboard")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LeaderboardGender.allCases, id: \.self) { gender in
                    LeaderboardChip(
                        title: SegmentMessages.gender(gender),
                        isOn: store.selection.gender == gender,
                        isLocked: store.isLocked(gender)
                    ) { store.tap(gender) }
                }
                Divider().frame(height: 24)
                ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                    chip(SegmentMessages.period(period), .period(period))
                }
                chip(SegmentMessages.following, .following)
                bandMenu(SegmentMessages.age, bands: LeaderboardFilter.ageBands, label: SegmentMessages.ageBand) { .age($0) }
                bandMenu(SegmentMessages.weight, bands: LeaderboardFilter.weightBands, label: SegmentMessages.weightBand) { .weight($0) }
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, _ filter: LeaderboardFilter) -> some View {
        LeaderboardChip(title: title, isOn: store.selection.filter == filter, isLocked: store.isLocked(filter)) {
            store.tap(filter)
        }
    }

    /// « Âge ▾ » and « Poids ▾ »: a menu of bands; a locked chip opens the Paywall instead.
    @ViewBuilder
    private func bandMenu(
        _ title: String,
        bands: [String],
        label: @escaping (String) -> String,
        filter: @escaping (String) -> LeaderboardFilter
    ) -> some View {
        let selected = bands.first { store.selection.filter == filter($0) }
        if store.isLocked(filter(bands[0])) {
            LeaderboardChip(title: title, isOn: false, isLocked: true) { store.tap(filter(bands[0])) }
        } else {
            Menu {
                ForEach(bands, id: \.self) { band in
                    Button(label(band)) {
                        if band != selected { store.tap(filter(band)) }
                    }
                }
                if let selected {
                    Button(SegmentMessages.removeFilter, role: .destructive) { store.tap(filter(selected)) }
                }
            } label: {
                LeaderboardChip(title: selected.map(label) ?? "\(title) ▾", isOn: selected != nil, isLocked: false) {}
                    .allowsHitTesting(false)
            }
        }
    }
}
