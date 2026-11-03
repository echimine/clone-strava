import SwiftUI

/// The detail's map, about 300 pt tall (ADR-036 §9): the route framed, "Départ et arrivée
/// masqués" when the privacy zone trimmed it, and ⤢. Tapping it, or ⤢, opens the full-screen
/// map; the inline map itself does not pan, so the page scrolls over it.
struct ActivityDetailMap: View {
    let route: EncodedPolyline
    let routeTrimmed: Bool
    /// The card of the Activity, for the full-screen summary.
    let post: ActivityPost

    @State private var showsFullScreen = false

    var body: some View {
        ActivityRouteMap(route: route)
            .allowsHitTesting(false)
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { showsFullScreen = true }
            .overlay(alignment: .bottomLeading) {
                if routeTrimmed {
                    RouteTrimmedLabel()
                        .padding(Theme.spacing / 2)
                        .accessibilityIdentifier("activityDetail.routeTrimmed")
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    showsFullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .glassBackground(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .padding(Theme.spacing / 2)
                .accessibilityLabel(ActivityAnalysisMessages.openMap)
                .accessibilityIdentifier("activityDetail.openMap")
            }
            .fullScreenCover(isPresented: $showsFullScreen) {
                ActivityFullScreenMap(route: route, routeTrimmed: routeTrimmed, post: post)
            }
    }
}
