import SwiftUI

/// Under the Map's mode selector, in Segments mode (ADR-039 §15): the chips Tous / Vélo /
/// Course / Marche / Randonnée and « Favoris », then « Zoome pour voir les Segments » or
/// « Rechercher dans cette zone » when it applies.
struct SegmentMapControls: View {
    let store: SegmentMapStore

    var body: some View {
        VStack(spacing: 8) {
            chips
            status
        }
        .animation(.default, value: store.isZoomedOut)
        .animation(.default, value: store.canSearchHere)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                SegmentChip(title: SegmentMapMessages.all, isOn: store.filter.sport == nil) {
                    Task { await store.select(sport: nil) }
                }
                ForEach(SegmentSport.allCases, id: \.self) { sport in
                    SegmentChip(
                        title: SegmentMapMessages.chip(sport),
                        symbol: ActivityFormatters.sportSymbol(sport.sportType),
                        isOn: store.filter.sport == sport
                    ) {
                        Task { await store.select(sport: sport) }
                    }
                }
                SegmentChip(title: SegmentMapMessages.favorites, symbol: "star.fill", isOn: store.filter.favoritesOnly) {
                    Task { await store.toggleFavoritesOnly() }
                }
            }
            .padding(.horizontal, Theme.spacing)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("segmentMap.chips")
    }

    @ViewBuilder private var status: some View {
        if store.isZoomedOut {
            Label(SegmentMapMessages.zoomIn, systemImage: "plus.magnifyingglass")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassBackground(in: Capsule())
                .accessibilityIdentifier("segmentMap.zoomIn")
                .transition(.opacity)
        } else if store.canSearchHere {
            Button {
                Task { await store.searchHere() }
            } label: {
                Label(SegmentMapMessages.searchHere, systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Capsule())
                    .glassBackground(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("segmentMap.searchHere")
            .transition(.opacity)
        }
    }
}

/// A filter chip: orange when on.
private struct SegmentChip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? .white : .primary)
            .background(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.regularMaterial), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
