import SwiftUI

/// Detail page pushed from Mes Itinéraires (ADR-030 §8): a scrolling page that works offline
/// from the cache. It closes by itself once the Itinerary is gone (`404`, deleted elsewhere).
/// `actions` is the toolbar slot for Modifier (#37), Renommer and Supprimer (#38).
struct ItineraryDetailView<Actions: View>: View {
    @State var store: ItineraryDetailStore
    @ViewBuilder var actions: () -> Actions

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            ItineraryDetailContent(store: store)
                .padding(.bottom, Theme.spacing)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(store.summary?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { actions() }
        }
        .task { await store.observe() }
        .onChange(of: store.isGone) { _, isGone in
            if isGone { dismiss() }
        }
        .accessibilityIdentifier("itineraryDetail")
    }
}

extension ItineraryDetailView where Actions == EmptyView {
    init(store: ItineraryDetailStore) {
        self.init(store: store, actions: { EmptyView() })
    }
}

/// What the detail shows, without its container: the page above, the Map tab sheet (#36).
/// Track, name and sport, distance, elevation gain, elevation profile, then the credit of
/// the altitudes. The Map tab sheet leaves the track out: the map behind it draws it.
struct ItineraryDetailContent: View {
    let store: ItineraryDetailStore
    var showsTrackMap = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if showsTrackMap {
                trackMap
            }
            if let summary = store.summary {
                header(summary)
                stats
                profileSection
            }
        }
    }

    @ViewBuilder private var trackMap: some View {
        Group {
            if let detail = store.detail {
                ItineraryTrackMap(track: detail.track)
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    if let message = store.trackMessage {
                        Label(message, systemImage: "wifi.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(Theme.spacing)
                            .accessibilityIdentifier("itineraryTrackMessage")
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func header(_ summary: ItinerarySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ActivityFormatters.sportLabel(summary.sport), systemImage: ActivityFormatters.sportSymbol(summary.sport))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(summary.name)
                .font(.title2.weight(.bold))
                .accessibilityIdentifier("itineraryDetailName")
        }
        .padding(.horizontal, Theme.spacing)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                stat("Distance", store.distanceText)
                Divider().frame(height: 36)
                stat("Dénivelé", store.elevationText)
            }
            .padding(.horizontal, -8)
        }
        .padding(.horizontal, Theme.spacing)
    }

    @ViewBuilder private var profileSection: some View {
        if let profile = store.profile, !profile.points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(ItineraryMessages.elevationProfile)
                    .font(.headline)
                ElevationProfileChart(profile: profile)
                    .frame(height: 160)
                if let source = store.elevationSourceText {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("itineraryElevationSource")
                }
            }
            .padding(Theme.spacing)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            .padding(.horizontal, Theme.spacing)
        }
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
        .accessibilityElement(children: .combine)
    }
}
