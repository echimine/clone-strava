import SwiftUI

extension RootView {
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
