import SwiftUI

/// Bottom of the Map in Segments mode (ADR-039 §15): « n Segments dans cette zone » and a
/// carousel of cards, nearest to the zone's centre first, like the Itineraries'. The centred
/// card is highlighted on the map through `SegmentMapStore.focusedPath`; a touch opens the
/// Segment's sheet. Nothing while zoomed out.
struct SegmentMapCarousel: View {
    @Bindable var store: SegmentMapStore
    let open: (String) -> Void

    var body: some View {
        content
            .accessibilityIdentifier("segmentMap.carousel")
            .toast($store.message)
    }

    @ViewBuilder private var content: some View {
        if store.isZoomedOut {
            EmptyView()
        } else if store.isLoading && store.segments.isEmpty {
            ProgressView()
                .accessibilityLabel("Chargement des Segments")
                .padding(12)
                .glassBackground(in: Circle())
                .frame(maxWidth: .infinity)
        } else if let failure = store.failure {
            notice(failure, symbol: "wifi.slash", identifier: "segmentMap.failure")
        } else if store.segments.isEmpty && store.searchedArea != nil {
            notice(store.emptyMessage, symbol: "point.topleft.down.to.point.bottomright.curvepath", identifier: "segmentMap.empty")
        } else if !store.segments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.countLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassBackground(in: Capsule())
                    .padding(.horizontal, Theme.spacing)
                    .accessibilityIdentifier("segmentMap.count")
                cards
            }
        }
    }

    private var cards: some View {
        // Not lazy, like the Itineraries' carousel: at most 50 cards.
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(store.segments) { segment in
                    SegmentMapCard(
                        segment: segment,
                        isFocused: store.focusedID == segment.id,
                        open: { open(segment.id) },
                        toggleStar: { Task { await store.toggleStar(segment.id) } }
                    )
                    .containerRelativeFrame(.horizontal) { width, _ in
                        width - 2 * Theme.spacing - (store.segments.count > 1 ? 24 : 0)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Theme.spacing, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $store.focusedID, anchor: .center)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: store.focusedID)
    }

    private func notice(_ text: String, symbol: String, identifier: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(Theme.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassBackground(in: .rect(cornerRadius: 20))
            .padding(.horizontal, Theme.spacing)
            .accessibilityIdentifier(identifier)
    }
}

/// One Segment: sport icon, name, verified badge, star; distance · grade (· category); athletes,
/// « Mon record » or the leader's time.
private struct SegmentMapCard: View {
    let segment: MapSegment
    let isFocused: Bool
    let open: () -> Void
    let toggleStar: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: ActivityFormatters.sportSymbol(segment.sport.sportType))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(segment.name)
                        .font(.headline)
                        .lineLimit(1)
                    if segment.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    // Room for the star, drawn over the card so its tap is its own.
                    Color.clear.frame(width: 32, height: 32)
                }
                Text(SegmentMapMessages.figures(segment))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                HStack {
                    Text(SegmentMapMessages.athletes(segment.athleteCount))
                    Spacer()
                    if let best = SegmentMapMessages.bestTime(segment) {
                        Label(best, systemImage: segment.myBestTime == nil ? "trophy" : "stopwatch")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(Theme.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.accent, lineWidth: isFocused ? 2 : 0))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityAction(named: segment.isStarred ? "Retirer des favoris" : "Ajouter aux favoris", toggleStar)
        .accessibilityIdentifier("segmentMapCard")
        .overlay(alignment: .topTrailing) {
            Button(action: toggleStar) {
                Image(systemName: segment.isStarred ? "star.fill" : "star")
                    .foregroundStyle(segment.isStarred ? .yellow : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: segment.isStarred)
            .padding(.top, 6)
            .padding(.trailing, 6)
            .accessibilityHidden(true)
            .accessibilityIdentifier("segmentMapCard.star")
        }
    }

    private var accessibilityValue: String {
        [
            ActivityFormatters.sportLabel(segment.sport.sportType),
            segment.isVerified ? SegmentMapMessages.verified : nil,
            segment.isStarred ? "Favori" : nil,
            SegmentMapMessages.figures(segment),
            SegmentMapMessages.athletes(segment.athleteCount),
            SegmentMapMessages.bestTime(segment),
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
