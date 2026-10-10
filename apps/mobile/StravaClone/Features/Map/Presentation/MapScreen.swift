import MapboxMaps
import SwiftUI

/// Map tab (ADR-027 §6): follows the user from the start. Without location permission,
/// falls back to Paris and offers to open Settings. "Créer" starts a new Itinerary
/// (ADR-030); the editor belongs to another feature, so the action is injected.
/// The bottom sheet (spec #22) rests at 30 % and opens in full; its content (the
/// Itineraries) is injected too, with the path it wants framed: when a path appears the
/// sheet goes back to 30 % and the map frames the path above it.
/// MapboxMaps reads the access token from `MBXAccessToken` (Info.plist).
struct MapScreen<Sheet: View>: View {
    var onCreateItinerary: () -> Void = {}
    /// Path drawn and framed on the map (an Itinerary touched in the sheet), if any.
    var focusedPath: [Coordinate]?
    @ViewBuilder var sheet: () -> Sheet

    private static var fallbackCamera: Viewport {
        .camera(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), zoom: 12)
    }
    private static var sheetFraction: CGFloat { 0.3 }

    @Environment(LocationPermissionService.self) private var permission
    @State private var viewport: Viewport = .followUser
    @State private var isSheetExpanded = false

    private var isLocationBlocked: Bool {
        permission.authorization == .denied || permission.authorization == .restricted
    }

    var body: some View {
        GeometryReader { proxy in
            let sheetLayout = BottomSheetLayout(
                availableHeight: proxy.size.height,
                collapsedFraction: Self.sheetFraction,
                topMargin: 8
            )
            ZStack {
                // Identifier on the map only: on the whole screen it would hide the overlay's.
                AppMap(viewport: $viewport, bottomInset: sheetLayout.height(isExpanded: false)) {
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

                BottomSheet(isExpanded: $isSheetExpanded, layout: sheetLayout, content: sheet)
            }
        }
        .onChange(of: isLocationBlocked, initial: true) { _, blocked in
            if blocked {
                viewport = Self.fallbackCamera
            }
        }
        .onChange(of: focusedPath) { previous, path in
            guard let path, path.count >= 2 else { return }
            // A new selection leaves a small sheet; a finer track for the same one only reframes.
            if previous == nil {
                isSheetExpanded = false
            }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 2)
        }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .accessibilityIdentifier("locationPermissionBanner")
    }
}

/// The framed path: an orange line, a green start and a red finish.
private struct FocusedPathContent: MapContent {
    let coordinates: [CLLocationCoordinate2D]

    var body: some MapContent {
        PolylineAnnotation(lineCoordinates: coordinates)
            .lineColor(UIColor(Theme.accent))
            .lineWidth(5)
            .lineJoin(.round)
        if let start = coordinates.first, let finish = coordinates.last {
            endpoint(start, color: UIColor(red: 0.18, green: 0.8, blue: 0.44, alpha: 1))
            endpoint(finish, color: UIColor(red: 0.91, green: 0.3, blue: 0.24, alpha: 1))
        }
    }

    private func endpoint(_ coordinate: CLLocationCoordinate2D, color: UIColor) -> CircleAnnotation {
        CircleAnnotation(centerCoordinate: coordinate)
            .circleColor(color)
            .circleRadius(7)
            .circleStrokeColor(.white)
            .circleStrokeWidth(2)
    }
}
