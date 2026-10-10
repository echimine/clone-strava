import SwiftUI

/// Bottom of the Map tab (spec #22, ADR-030 §8): the Itinerary cards from the cache (offline
/// too) in a horizontal carousel, resynced each time it shows. Once scrolled, the centred card
/// is framed on the map through `MapItinerariesStore.focusedPath`; a touch pushes its detail.
struct MapItinerariesCarousel: View {
    @Bindable var store: MapItinerariesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            syncBanner
            content
        }
        .animation(.default, value: store.list.syncMessage)
        .task(id: store.list.limit) { await store.list.observe() }
        .task { await store.appeared() }
        .accessibilityIdentifier("mapItineraries.carousel")
    }

    @ViewBuilder private var content: some View {
        let list = store.list
        if !list.hasLoaded {
            ProgressView()
                .padding(12)
                .glassBackground(in: Circle())
                .frame(maxWidth: .infinity)
        } else if list.isEmpty {
            Label(ItineraryMessages.emptyDescription, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(Theme.spacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassBackground(in: .rect(cornerRadius: 20))
                .padding(.horizontal, Theme.spacing)
                .accessibilityIdentifier("mapItineraries.empty")
        } else {
            // Not lazy: a LazyHStack paged by `scrollPosition` keeps re-measuring its estimates.
            // A page is a few cards; the next one loads when the last card is centred.
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(list.itineraries) { itinerary in
                        NavigationLink(value: itinerary.id) {
                            MapItineraryCard(itinerary: itinerary)
                        }
                        .buttonStyle(.plain)
                        // With more than one card, the next one peeks out on the right.
                        .containerRelativeFrame(.horizontal) { width, _ in
                            width - 2 * Theme.spacing - (list.itineraries.count > 1 ? 24 : 0)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.spacing, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $store.focusedID, anchor: .center)
            .scrollIndicators(.hidden)
            // Room for the cards' shadow, which the scroll view would clip.
            .scrollClipDisabled()
            .sensoryFeedback(.selection, trigger: store.focusedID)
            .onChange(of: store.focusedID) {
                if let focused = store.focused {
                    list.loadMoreIfNeeded(current: focused)
                }
            }
        }
    }

    @ViewBuilder private var syncBanner: some View {
        if let message = store.list.syncMessage {
            Label(message, systemImage: "wifi.slash")
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassBackground(in: Capsule())
                .padding(.horizontal, Theme.spacing)
                .transition(.opacity)
                .accessibilityIdentifier("mapItinerariesSyncMessage")
        }
    }
}

/// One Itinerary in the carousel: sport, name, distance and elevation gain. No thumbnail:
/// the map behind draws the path.
private struct MapItineraryCard: View {
    let itinerary: ItinerarySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: ActivityFormatters.sportSymbol(itinerary.sport))
                    .foregroundStyle(Theme.accent)
                Text(itinerary.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: Theme.spacing) {
                stat("Distance", ActivityFormatters.distance(itinerary.distance))
                stat("Dénivelé", ActivityFormatters.elevation(itinerary.elevationGain))
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mapItineraryCard")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
