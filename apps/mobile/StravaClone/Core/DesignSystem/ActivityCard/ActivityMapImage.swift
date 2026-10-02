import SwiftUI

/// Static map of the route (ADR-029), or a sport placeholder when there is no route to show
/// (indoor, everything inside the privacy zone) or no Mapbox token.
struct ActivityMapImage: View {
    let route: EncodedPolyline?
    let sport: SportType

    @Environment(\.mapboxAccessToken) private var accessToken

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    RemoteImage(url: url(for: proxy.size)) { placeholder }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .clipped()
            .accessibilityLabel("Carte du parcours")
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
