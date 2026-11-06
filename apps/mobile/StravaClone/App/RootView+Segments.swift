import SwiftUI

/// The Segment screens the shell builds (ADR-039 §15): the creation, drawn with the Itinerary
/// editor, Plus › « Segments », and a Segment's sheet and Leaderboard pushed in any stack, with
/// the Paywall their locks open (ADR-007 rule 5).
struct SegmentScreens {
    let makeCanvas: @MainActor (SegmentSport, @escaping () -> Void) -> SegmentDrawingCanvas
    let makeDrawingStore: @MainActor (SegmentSport) -> SegmentDrawingStore
    let makeCreateStore: @MainActor (SegmentCandidate) -> SegmentCreateStore
    let makeFavoritesStore: @MainActor () -> FavoriteSegmentsStore
    let makeSheetStore: @MainActor (String, @escaping @MainActor () -> Void) -> SegmentSheetStore
    let makeLeaderboardStore: @MainActor (String) -> LeaderboardStore
    let makePaywallStore: @MainActor (AnalyticsEvent.PaywallEntry, @escaping @MainActor () -> Void) -> PaywallStore

    @MainActor
    init(di: Di) {
        makeCanvas = { [di] sport, onClose in di.makeSegmentDrawingCanvas(sport: sport, onClose: onClose) }
        makeDrawingStore = { [di] sport in di.makeSegmentDrawingStore(sport: sport) }
        makeCreateStore = { [di] candidate in di.makeSegmentCreateStore(candidate: candidate) }
        makeFavoritesStore = di.makeFavoriteSegmentsStore
        makeSheetStore = { [di] id, onDeleted in di.makeSegmentSheetStore(id: id, onDeleted: onDeleted) }
        makeLeaderboardStore = { [di] id in di.makeLeaderboardStore(id: id) }
        makePaywallStore = { [di] entry, finish in di.makeSegmentPaywallStore(entry: entry, finish: finish) }
    }

    /// Plus › « Segments », with its « + ».
    @MainActor
    func favorites(_ flow: SegmentCreationFlow) -> AnyView {
        AnyView(FavoriteSegmentsView(makeStore: makeFavoritesStore, onCreate: { flow.start(from: .mySegments) }))
    }
}

extension View {
    /// The creation of a Segment in full screen, over the tabs, and its « Connexion requise ».
    func segmentCreation(
        _ flow: SegmentCreationFlow,
        screens: SegmentScreens,
        destinations: AppDestinations,
        onShowMySegments: @escaping @MainActor () -> Void
    ) -> some View {
        fullScreenCover(isPresented: Bindable(flow).isPresented) {
            SegmentCreationView(
                makeCanvas: screens.makeCanvas,
                makeDrawingStore: screens.makeDrawingStore,
                makeCreateStore: screens.makeCreateStore,
                destinations: destinations,
                onShowMySegments: {
                    flow.isPresented = false
                    onShowMySegments()
                },
                onClose: { flow.isPresented = false }
            )
        }
        .toast(Bindable(flow).toast)
    }
}

extension RootView {
    /// « Voir mes Segments » after a creation: Plus › « Segments », already under the flow
    /// when it was opened from there.
    func showMySegments() {
        guard segmentCreation.entry == .mapTab else { return }
        profileStore.path = NavigationPath([ProfileStore.Destination.segments])
        selectedTab = .profile
    }

    /// A Segment's sheet (ADR-039 §15), pushed in the stack of `path`; the Paywall its locks
    /// open, in a sheet, is the one of the Onboarding with its `entry`.
    func segmentSheet(_ request: SegmentRequest, path: Binding<NavigationPath>) -> some View {
        SegmentSheetPage(
            request: request,
            makeStore: segmentScreens.makeSheetStore,
            makeLeaderboardStore: segmentScreens.makeLeaderboardStore,
            paywall: { [authStore, segmentScreens] entry, close in
                let firstName = if case .signedIn(let user) = authStore.state { user.firstName } else { "" }
                return AnyView(PaywallView(store: segmentScreens.makePaywallStore(entry, close), firstName: firstName))
            },
            onDeleted: {
                if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() }
            }
        )
    }
}
