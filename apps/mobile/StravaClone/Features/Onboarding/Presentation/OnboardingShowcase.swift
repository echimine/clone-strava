import SwiftUI

/// "Voici ce qui vous attend" (ADR-035 §1): four pages to swipe, each with an animated mock of
/// the app (recording, itineraries, feed, segments), and "Passer" at the top right.
struct OnboardingShowcase: View {
    let firstName: String
    /// The first sport picked: the one being recorded on the first page.
    let sport: SportType
    let finish: () -> Void

    @State private var page = 0

    private static let pages: [(title: String, text: String)] = [
        ("Enregistrez chaque sortie", "Distance, allure, dénivelé : tout s'enregistre, même sans réseau."),
        ("Planifiez vos itinéraires", "Tracez un parcours, voyez son dénivelé, et partez."),
        ("Partagez vos efforts", "Vos amis vous suivent, vous envoient des kudos et vous encouragent."),
        ("Mesurez vos progrès", "Segments, classements et records : battez-vous contre vous-même."),
    ]

    private var isLastPage: Bool { page == Self.pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(firstName.isEmpty ? "Voici ce qui vous attend" : "\(firstName), voici ce qui vous attend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Passer", action: finish)
                    .accessibilityHint("Passe la présentation")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.showcase.skip")
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 10)

            TabView(selection: $page) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    VStack(spacing: 0) {
                        stage(index)
                            .frame(maxHeight: .infinity)
                        VStack(spacing: 10) {
                            Text(Self.pages[index].title)
                                .font(.system(size: 28, weight: .bold))
                                .tracking(-0.4)
                            Text(Self.pages[index].text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageIndicator
                .padding(.vertical, 14)

            Button(isLastPage ? "C'est parti" : "Suivant") {
                if isLastPage {
                    finish()
                } else {
                    withAnimation(.snappy) { page += 1 }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("onboarding.showcase.next")
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 10)
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Self.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.accent : Color(.systemGray4))
                    .frame(width: index == page ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) sur \(Self.pages.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if page < Self.pages.count - 1 { withAnimation(.snappy) { page += 1 } }
            case .decrement: if page > 0 { withAnimation(.snappy) { page -= 1 } }
            @unknown default: break
            }
        }
    }

    /// The phone-like card on its orange halo.
    private func stage(_ index: Int) -> some View {
        ZStack {
            RadialGradient(
                colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0)],
                center: .center,
                startRadius: 10,
                endRadius: 230
            )
            Group {
                switch index {
                case 0: ShowcaseRecordMock(sport: sport)
                case 1: ShowcaseItineraryMock()
                case 2: ShowcaseFeedMock(sport: sport)
                default: ShowcaseLeaderboardMock()
                }
            }
            .frame(width: 260, height: 330)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(.systemBackground)))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(.separator).opacity(0.5)))
            .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
            .accessibilityHidden(true)
        }
    }
}

#if DEBUG
#Preview {
    OnboardingShowcase(firstName: "Camille", sport: .ride) {}
}
#endif
