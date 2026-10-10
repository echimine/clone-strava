import SwiftUI

/// Profil > Mes Itinéraires (ADR-030 §8): feed-style cards from the cache, most recently
/// updated first, page by page; a full resync on opening and on pull-to-refresh.
/// "Créer" is injected: the app shell opens the editor, or says a connection is required.
struct MyItinerariesView: View {
    @Bindable var store: ItineraryListStore
    let onCreate: () -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(ItineraryMessages.myItineraries)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onCreate) {
                        Label(ItineraryMessages.create, systemImage: "plus")
                    }
                    .accessibilityIdentifier("createItineraryFromList")
                }
            }
            .task(id: store.limit) { await store.observe() }
            .task { await store.refresh() }
    }

    @ViewBuilder private var content: some View {
        if !store.hasLoaded {
            ProgressView()
        } else if store.isEmpty {
            ScrollView {
                syncBanner
                ContentUnavailableView {
                    Label(ItineraryMessages.emptyTitle, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                } description: {
                    Text(ItineraryMessages.emptyDescription)
                } actions: {
                    Button(ItineraryMessages.create, action: onCreate)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("createFirstItinerary")
                }
                .padding(.top, 80)
            }
            .refreshable { await store.refresh() }
        } else {
            ScrollView {
                syncBanner
                LazyVStack(spacing: Theme.spacing) {
                    ForEach(store.itineraries) { itinerary in
                        ItineraryCard(itinerary: itinerary)
                            .onAppear { store.loadMoreIfNeeded(current: itinerary) }
                    }
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 8)
            }
            .refreshable { await store.refresh() }
            .accessibilityIdentifier("itineraries.list")
        }
    }

    @ViewBuilder private var syncBanner: some View {
        if let message = store.syncMessage {
            Label(message, systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 8)
                .accessibilityIdentifier("itinerariesSyncMessage")
        }
    }
}
