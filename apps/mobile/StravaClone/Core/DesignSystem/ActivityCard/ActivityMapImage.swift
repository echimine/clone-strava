import SwiftUI

/// Static map of the route (ADR-029), or a sport placeholder when there is no route to show
/// (indoor, everything inside the privacy zone) or no Mapbox token. "Départ et arrivée
/// masqués" when the privacy zone removed part of the route (ADR-036 §5). 16:9, or `height`
/// tall as a slide of the card's carousel (ADR-037 §10).
struct ActivityMapImage: View {
    let route: EncodedPolyline?
    let sport: SportType
    var routeTrimmed = false
    var height: CGFloat?

    @Environment(\.mapboxAccessToken) private var accessToken

    var body: some View {
        frame
            .overlay {
                GeometryReader { proxy in
                    RemoteImage(url: url(for: proxy.size)) { placeholder }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if routeTrimmed && route != nil {
                    RouteTrimmedLabel()
                        .padding(8)
                        .accessibilityIdentifier("activityCard.routeTrimmed")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(routeTrimmed && route != nil ? "Carte du parcours, \(ActivityCardMessages.routeTrimmed.lowercased())" : "Carte du parcours")
    }

    @ViewBuilder private var frame: some View {
        if let height {
            Color.clear.frame(maxWidth: .infinity).frame(height: height)
        } else {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit)
        }
    }

    private func url(for size: CGSize) -> URL? {
        route.flatMap { StaticMapURL.make(route: $0, size: size, accessToken: accessToken) }
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: ActivityFormatters.sportSymbol(sport))
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
        }
    }
}
