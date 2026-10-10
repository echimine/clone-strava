import SwiftUI

/// One Itinerary in Mes Itinéraires, feed style (ADR-030 §8): name, sport, distance,
/// elevation gain and thumbnail.
struct ItineraryCard: View {
    let itinerary: ItinerarySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Label(ActivityFormatters.sportLabel(itinerary.sport), systemImage: ActivityFormatters.sportSymbol(itinerary.sport))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(itinerary.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                HStack(alignment: .top, spacing: 0) {
                    stat("Distance", ActivityFormatters.distance(itinerary.distance))
                    Divider().frame(height: 36)
                    stat("Dénivelé", ActivityFormatters.elevation(itinerary.elevationGain))
                }
                .padding(.horizontal, -8)
            }
            .padding([.horizontal, .top], Theme.spacing)

            ItineraryThumbnail(mapPolyline: itinerary.mapPolyline)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("itineraryCard")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

/// Mapbox static image of the Itinerary; when it is missing (offline and not cached, no
/// token), the `mapPolyline` drawn locally on a neutral background (ADR-030 §8).
struct ItineraryThumbnail: View {
    let mapPolyline: EncodedPolyline

    @Environment(\.mapboxAccessToken) private var accessToken

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    RemoteImage(url: StaticMapURL.make(route: mapPolyline, size: proxy.size, accessToken: accessToken)) {
                        sketch
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .clipped()
            .accessibilityLabel("Carte de l'Itinéraire")
    }

    private var sketch: some View {
        ZStack {
            Color(.tertiarySystemFill)
            PolylineSketch(coordinates: mapPolyline.decode(), inset: 24)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .accessibilityIdentifier("itineraryThumbnailSketch")
    }
}

#Preview {
    ScrollView {
        ItineraryCard(itinerary: ItinerarySummary(
            id: ItineraryID(),
            name: "Tour du lac d'Annecy",
            sport: .ride,
            distance: Distance(meters: 42_195),
            elevationGain: 640,
            mapPolyline: EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"),
            updatedAt: .now
        ))
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
