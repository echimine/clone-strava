import MapboxMaps
import SwiftUI

/// Map tab (ADR-027 §6): follows the user from the start. Without location permission,
/// falls back to Paris and offers to open Settings. "Créer" starts a new Itinerary
/// (ADR-030); the editor belongs to another feature, so the action is injected.
/// The bottom content (spec #22: the Itineraries carousel) is injected too, with the path it
/// wants framed above it. It sits in a navigation stack, so what it pushes covers the map.
/// MapboxMaps reads the access token from `MBXAccessToken` (Info.plist).
struct MapScreen<Bottom: View>: View {
    var onCreateItinerary: () -> Void = {}
    /// Path drawn and framed on the map (the Itinerary centred in the carousel), if any.
    var focusedPath: [Coordinate]?
    @ViewBuilder var bottom: () -> Bottom

    private static var fallbackCamera: Viewport {
        .camera(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), zoom: 12)
    }

    @Environment(LocationPermissionService.self) private var permission
    @State private var viewport: Viewport = .followUser
    @State private var bottomHeight: CGFloat = 0

    private var isLocationBlocked: Bool {
        permission.authorization == .denied || permission.authorization == .restricted
    }

    var body: some View {
        // Identifier on the map only: on the whole screen it would hide the overlays'.
        AppMap(viewport: $viewport, bottomInset: bottomHeight) {
            if let focusedPath, focusedPath.count >= 2 {
                FocusedPathContent(coordinates: focusedPath.map(\.locationCoordinate))
            }
        }
        .accessibilityIdentifier("mapScreen")
        .overlay(alignment: .top) {
            VStack(alignment: .trailing, spacing: 8) {
                if isLocationBlocked {
                    locationBanner
                }
                createItineraryButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .overlay(alignment: .bottom) {
            bottom()
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { bottomHeight = $0 }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: isLocationBlocked, initial: true) { _, blocked in
            if blocked {
                viewport = Self.fallbackCamera
            }
        }
        .onChange(of: focusedPath) { _, path in
            guard let path, path.count >= 2 else { return }
            withViewportAnimation(.easeOut(duration: 0.6)) {
                viewport = .overview(
                    geometry: LineString(path.map(\.locationCoordinate)),
                    geometryPadding: EdgeInsets(top: 72, leading: 40, bottom: 32, trailing: 40)
                )
            }
        }
    }

    private var createItineraryButton: some View {
        Button(action: onCreateItinerary) {
            Label("Créer", systemImage: "plus")
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Capsule())
                .glassBackground(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .accessibilityLabel("Créer un Itinéraire")
        .accessibilityIdentifier("createItineraryButton")
    }

    private var locationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
            Text("Autorisez la localisation pour voir votre position.")
                .font(.footnote)
            Spacer(minLength: 0)
            Button("Réglages", action: permission.openSettings)
                .font(.footnote.bold())
        }
        .padding(12)
        .glassBackground(in: .rect(cornerRadius: 12))
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .accessibilityIdentifier("locationPermissionBanner")
    }
}

/// The framed path: an orange line with its start and finish markers.
private struct FocusedPathContent: MapContent {
    let coordinates: [CLLocationCoordinate2D]

    var body: some MapContent {
        PolylineAnnotation(lineCoordinates: coordinates)
            .lineColor(UIColor(Theme.accent))
            .lineWidth(5)
            .lineJoin(.round)
        RouteEndpointsContent(coordinates: coordinates)
    }
}
