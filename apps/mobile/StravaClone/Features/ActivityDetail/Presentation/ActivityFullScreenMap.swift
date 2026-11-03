import MapboxMaps
import SwiftUI

/// The full-screen map of an Activity (ADR-036 §9): pan and zoom on the route, Fermer, a
/// button that frames the route again once moved, and Distance · Allure (Vitesse) · Temps. No draggable
/// sheet.
struct ActivityFullScreenMap: View {
    let route: EncodedPolyline
    let routeTrimmed: Bool
    let post: ActivityPost

    @State private var viewport: Viewport
    @Environment(\.dismiss) private var dismiss

    private let line: [CLLocationCoordinate2D]

    init(route: EncodedPolyline, routeTrimmed: Bool, post: ActivityPost) {
        self.route = route
        self.routeTrimmed = routeTrimmed
        self.post = post
        let line = route.decode().map(\.locationCoordinate)
        self.line = line
        _viewport = State(initialValue: Self.overview(line))
    }

    /// The route framed, with room for the buttons above and the summary below.
    private static func overview(_ line: [CLLocationCoordinate2D]) -> Viewport {
        .overview(
            geometry: LineString(line),
            geometryPadding: EdgeInsets(top: 96, leading: 32, bottom: 160, trailing: 32)
        )
    }

    var body: some View {
        Map(viewport: $viewport) {
            PolylineAnnotation(lineCoordinates: line)
                .lineColor(UIColor(Theme.accent))
                .lineWidth(4)
                .lineJoin(.round)
            RouteEndpointsContent(coordinates: line)
        }
        .mapStyle(.outdoors)
        .gestureOptions(GestureOptions(rotateEnabled: false, pitchEnabled: false))
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .bottom) { bottomBar }
        .accessibilityIdentifier("activityDetail.fullScreenMap")
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassBackground(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(Theme.spacing)
        .accessibilityLabel(ActivityAnalysisMessages.closeMap)
        .accessibilityIdentifier("activityDetail.closeMap")
    }

    private var bottomBar: some View {
        VStack(alignment: .trailing, spacing: 12) {
            HStack(alignment: .bottom) {
                if routeTrimmed {
                    RouteTrimmedLabel()
                }
                Spacer(minLength: 0)
                // Shown once the camera left the route.
                if viewport.overview == nil {
                    recentreButton
                }
            }
            summary
        }
        .padding(Theme.spacing)
    }

    private var recentreButton: some View {
        Button {
            withViewportAnimation {
                viewport = Self.overview(line)
            }
        } label: {
            Image(systemName: "scope")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .glassBackground(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ActivityAnalysisMessages.recentre)
        .accessibilityIdentifier("activityDetail.recentreMap")
    }

    /// Distance · Allure · Temps (Vitesse for a `speed` sport, ADR-036 §9).
    private var summary: some View {
        HStack(spacing: 0) {
            ForEach(ActivityCardStat.mapSummary(for: post), id: \.label) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(stat.value)
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Theme.spacing)
        .glassBackground(in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("activityDetail.mapSummary")
    }
}
