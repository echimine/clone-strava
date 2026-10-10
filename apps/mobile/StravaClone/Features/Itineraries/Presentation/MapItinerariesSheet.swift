import SwiftUI

/// Content of the Map tab sheet (spec #22, ADR-030 §8): the Itinerary cards from the cache
/// (offline too), resynced each time the sheet shows; a card touched shows its detail in
/// the sheet, while the app shell frames the map on `MapItinerariesStore.focusedPath`.
struct MapItinerariesSheet: View {
    let store: MapItinerariesStore

    var body: some View {
        Group {
            if let detail = store.detail {
                MapItineraryDetailPane(store: detail, onClose: store.closeDetail)
                    .id(detail.id)
            } else {
                list
            }
        }
        .animation(.default, value: store.detail?.id)
        .task(id: store.list.limit) { await store.list.observe() }
        .task { await store.sheetOpened() }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(ItineraryMessages.myItineraries)
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, Theme.spacing)
                syncBanner
                cards
            }
            .padding(.bottom, Theme.spacing)
        }
        .refreshable { await store.list.refresh() }
        .accessibilityIdentifier("mapItineraries.list")
    }

    @ViewBuilder private var cards: some View {
        let list = store.list
        if !list.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.spacing)
        } else if list.isEmpty {
            Text(ItineraryMessages.emptyDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.spacing)
                .accessibilityIdentifier("mapItineraries.empty")
        } else {
            LazyVStack(spacing: Theme.spacing) {
                ForEach(list.itineraries) { itinerary in
                    Button { store.select(itinerary) } label: {
                        ItineraryCard(itinerary: itinerary)
                    }
                    .buttonStyle(.plain)
                    .onAppear { list.loadMoreIfNeeded(current: itinerary) }
                }
            }
            .padding(.horizontal, Theme.spacing)
        }
    }

    @ViewBuilder private var syncBanner: some View {
        if let message = store.list.syncMessage {
            Label(message, systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.spacing)
                .accessibilityIdentifier("mapItinerariesSyncMessage")
        }
    }
}

/// The touched Itinerary in the sheet: name and figures first, so the small sheet shows
/// them; opened in full, the elevation profile. The map behind draws the track.
private struct MapItineraryDetailPane: View {
    let store: ItineraryDetailStore
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            ItineraryDetailContent(store: store, showsTrackMap: false)
                .padding(.bottom, Theme.spacing)
        }
        // On the scroll view only: on the whole pane it would hide the close button's.
        .accessibilityIdentifier("mapItineraryDetail")
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .padding(.trailing, Theme.spacing)
            .accessibilityLabel(ItineraryMessages.backToList)
            .accessibilityIdentifier("mapItineraryDetail.close")
        }
        .task { await store.observe() }
    }
}
