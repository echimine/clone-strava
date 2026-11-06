import SwiftUI

/// The detail's map, a slide of the header's carousel (ADR-036 §9, ADR-037 §10): the route
/// framed, "Départ et arrivée masqués" when the privacy zone trimmed it, and ⤢. Tapping it, or
/// ⤢, opens the full-screen map; the inline map itself does not pan, so the page and the
/// carousel scroll over it.
struct ActivityDetailMap: View {
    let route: EncodedPolyline
    let routeTrimmed: Bool
    /// The card of the Activity, for the full-screen summary.
    let post: ActivityPost
    /// The medalled Segments' ribbons, at their starts (spec #252).
    var segmentMedals: [SegmentMedalMark] = []
    var height: CGFloat = 330

    @State private var showsFullScreen = false

    var body: some View {
        ActivityRouteMap(route: route, segmentMedals: segmentMedals)
            .allowsHitTesting(false)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { showsFullScreen = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(ActivityAnalysisMessages.openMap)
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
                ActivityFullScreenMap(route: route, routeTrimmed: routeTrimmed, post: post, segmentMedals: segmentMedals)
            }
    }
}
