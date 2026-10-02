import MapboxMaps
import SwiftUI

/// Map tab (ADR-027 §6): follows the user from the start. Without location permission,
/// falls back to Paris and offers to open Settings.
/// MapboxMaps reads the access token from `MBXAccessToken` (Info.plist).
struct MapScreen: View {
    private static let fallbackCamera = Viewport.camera(
        center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
        zoom: 12
    )

    @Environment(LocationPermissionService.self) private var permission
    @State private var viewport: Viewport = .followUser

    private var isLocationBlocked: Bool {
        permission.authorization == .denied || permission.authorization == .restricted
    }

    var body: some View {
        AppMap(viewport: $viewport) {}
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                if isLocationBlocked {
                    locationBanner
                }
            }
            .onChange(of: isLocationBlocked, initial: true) { _, blocked in
                if blocked {
                    viewport = Self.fallbackCamera
                }
            }
            .accessibilityIdentifier("mapScreen")
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .accessibilityIdentifier("locationPermissionBanner")
    }
}
