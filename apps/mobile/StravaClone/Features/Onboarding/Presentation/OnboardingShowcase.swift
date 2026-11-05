import SwiftUI

/// "Voici ce qui vous attend" (ADR-035 §1): four full-bleed pages to swipe, each with a large,
/// animated mock of an app screen (recording, itineraries, feed, segments) on a dark gradient,
/// the title in white at the bottom over a fade, and "Passer" at the top right.
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
        ZStack {
            background
            TabView(selection: $page) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    pageContent(index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                header
                Spacer()
                pageIndicator
                    .padding(.bottom, 16)
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
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: page)
    }

    /// A dark vertical gradient with an orange glow that follows the page.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.03, green: 0.03, blue: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.45), Theme.accent.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 10,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Text(firstName.isEmpty ? "Voici ce qui vous attend" : "\(firstName), voici ce qui vous attend")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Passer", action: finish)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityIdentifier("onboarding.showcase.skip")
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 10)
    }

    /// One page: the big mock up top, the title and text at the bottom over a fade to black.
    private func pageContent(_ index: Int) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)
            mock(index)
                .frame(width: 290, height: 380)
                .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.white))
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                // The mock is drawn for the light scheme, whatever the page around it.
                .environment(\.colorScheme, .light)
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                .accessibilityHidden(true)
            Spacer(minLength: 24)
            VStack(spacing: 12) {
                Text(Self.pages[index].title)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                Text(Self.pages[index].text)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
            // Room for the dots and the button that float over the pages.
            .padding(.bottom, 130)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func mock(_ index: Int) -> some View {
        switch index {
        case 0: ShowcaseRecordMock(sport: sport)
        case 1: ShowcaseItineraryMock()
        case 2: ShowcaseFeedMock(sport: sport)
        default: ShowcaseLeaderboardMock()
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Self.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.accent : Color.white.opacity(0.3))
                    .frame(width: index == page ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) sur \(Self.pages.count)")
    }
}

#if DEBUG
#Preview {
    OnboardingShowcase(firstName: "Camille", sport: .ride) {}
}
#endif
