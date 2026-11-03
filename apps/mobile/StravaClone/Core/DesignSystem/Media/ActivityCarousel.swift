import SwiftUI

/// The map and the Media of an Activity, as on Strava (ADR-037 §10): the card's carousel (feed,
/// Activités tab, about 250 pt) and the detail's header (edge to edge, about 330 pt). Slides are
/// 86 % of the width, 4 pt apart, the next one peeking, and scrolling stops on a slide. A
/// single slide fills the width, without a carousel; no slide shows nothing (the caller keeps
/// its placeholder). The current slide's video plays muted and looped.
///
/// The map slide is the caller's (static map on the card, live map in the detail), so is what
/// a tap on it does. A tap on a Media calls `onTapMedia` (the viewer); without it, the tap goes
/// to what is behind (the card opens the detail).
struct ActivityCarousel<MapSlide: View>: View {
    let slides: [ActivitySlide<ActivityMedia>]
    let height: CGFloat
    /// Corner radius of each slide when several are shown (the card's slides are rounded).
    var slideCornerRadius: CGFloat = 0
    var onTapMedia: ((ActivityMedia) -> Void)?
    @ViewBuilder let map: () -> MapSlide

    @State private var currentID: ActivitySlide<ActivityMedia>.ID?

    var body: some View {
        if slides.count == 1, let only = slides.first {
            slide(only, isCurrent: true)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
        } else if !slides.isEmpty {
            peeking
        }
    }

    private var peeking: some View {
        let current = currentID ?? slides.first?.id
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 4) {
                ForEach(slides) { item in
                    slide(item, isCurrent: item.id == current)
                        .frame(height: height)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.86 }
                        .clipShape(.rect(cornerRadius: slideCornerRadius))
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentID)
        .frame(height: height)
        .accessibilityIdentifier("activityCarousel")
    }

    @ViewBuilder
    private func slide(_ item: ActivitySlide<ActivityMedia>, isCurrent: Bool) -> some View {
        switch item {
        case .map:
            map()
        case .media(let media):
            if let onTapMedia {
                ActivityMediaSlide(media: media, isCurrent: isCurrent)
                    .contentShape(.rect)
                    .onTapGesture { onTapMedia(media) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onTapMedia(media) }
                    .accessibilityIdentifier("activityCarousel.media")
            } else {
                ActivityMediaSlide(media: media, isCurrent: isCurrent)
                    .accessibilityIdentifier("activityCarousel.media")
            }
        }
    }
}
