import MapboxMaps
import SwiftUI

/// Itinerary editor (ADR-030 §2): centered on the athlete (ADR-027), each tap on the map
/// adds a Waypoint at the end; the stats card shows the sport and the distance.
struct ItineraryEditorView: View {
    @State var store: ItineraryEditorStore
    let onClose: () -> Void

    @State private var viewport: Viewport = .followUser

    var body: some View {
        AppMap(viewport: $viewport) {
            PolylineAnnotationGroup(store.lines.filter { !$0.isProvisional }) { line in
                PolylineAnnotation(lineCoordinates: line.coordinates.map(\.locationCoordinate))
                    .lineColor(UIColor(Theme.accent))
                    .lineWidth(5)
            }
            .lineCap(.round)
            .lineJoin(.round)

            PolylineAnnotationGroup(store.lines.filter(\.isProvisional)) { line in
                PolylineAnnotation(lineCoordinates: line.coordinates.map(\.locationCoordinate))
                    .lineColor(UIColor(Theme.accent).withAlphaComponent(0.7))
                    .lineWidth(4)
            }
            .lineDashArray([1, 1.5])

            CircleAnnotationGroup(store.markers) { marker in
                CircleAnnotation(centerCoordinate: marker.coordinate.locationCoordinate)
                    .circleRadius(marker.role == .waypoint ? 6 : 8)
                    .circleColor(Self.color(of: marker.role))
                    .circleStrokeColor(.white)
                    .circleStrokeWidth(2)
            }

            TapInteraction { context in
                store.tap(at: Coordinate(context.coordinate))
                return true
            }
        }
        // Identifier on the map only: on the whole screen it would hide the overlays'.
        .accessibilityIdentifier("itineraryEditor")
        .overlay(alignment: .top) { header }
        .safeAreaInset(edge: .bottom) { statsCard }
    }

    private static func color(of role: ItineraryEditorStore.Marker.Role) -> UIColor {
        switch role {
        case .start: UIColor(red: 0.18, green: 0.8, blue: 0.44, alpha: 1)
        case .waypoint: UIColor(Theme.accent)
        case .finish: UIColor(red: 0.91, green: 0.3, blue: 0.24, alpha: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Fermer l'éditeur")
            .accessibilityIdentifier("closeItineraryEditor")

            if let message = store.message {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("OK", action: store.dismissMessage)
                        .font(.footnote.bold())
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("itineraryEditorMessage")
            } else if let hint = store.hint {
                Text(hint)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .animation(.default, value: store.message)
    }

    private var statsCard: some View {
        HStack(spacing: Theme.spacing) {
            Label(store.sportLabel, systemImage: store.sportSymbol)
                .font(.subheadline.weight(.semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.distanceText)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("itineraryDistance")
                Text("Distance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.spacing)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, Theme.spacing)
        .padding(.bottom, 8)
        .animation(.default, value: store.distanceText)
    }
}
