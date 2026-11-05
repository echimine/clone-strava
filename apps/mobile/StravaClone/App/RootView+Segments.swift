import SwiftUI

/// Tabs of the signed-in app; Save brings the athlete back to the feed (ADR-031 §11).
enum AppTab: Hashable {
    case feed, map, record, profile
}

/// The Segment screens the shell builds (ADR-039 §15): the creation, drawn with the Itinerary
/// editor, and Plus › « Segments ».
struct SegmentScreens {
    let makeCanvas: @MainActor (SegmentSport, @escaping () -> Void) -> SegmentDrawingCanvas
    let makeDrawingStore: @MainActor (SegmentSport) -> SegmentDrawingStore
    let makeCreateStore: @MainActor (SegmentCandidate) -> SegmentCreateStore
    let makeStarredStore: @MainActor () -> StarredSegmentsStore

    @MainActor
    init(di: Di) {
        makeCanvas = { [di] sport, onClose in di.makeSegmentDrawingCanvas(sport: sport, onClose: onClose) }
        makeDrawingStore = { [di] sport in di.makeSegmentDrawingStore(sport: sport) }
        makeCreateStore = { [di] candidate in di.makeSegmentCreateStore(candidate: candidate) }
        makeStarredStore = di.makeStarredSegmentsStore
    }

    /// Plus › « Segments », with its « + ».
    @MainActor
    func starred(_ flow: SegmentCreationFlow) -> AnyView {
        AnyView(StarredSegmentsView(makeStore: makeStarredStore, onCreate: { flow.start(from: .mySegments) }))
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

    /// Debug builds only: the splash and celebration preview, reached from the Profile tab.
    static var animationsPreview: AnyView? {
        #if DEBUG
        AnyView(AnimationsPreviewView())
        #else
        nil
        #endif
    }
}
