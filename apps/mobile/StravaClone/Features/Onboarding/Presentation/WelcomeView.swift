import SwiftUI

/// The Welcome's two ways in: both lead to the account screen.
enum WelcomeEntry: Hashable {
    case createAccount, signIn
}

/// The first screen of someone signed out (ADR-035 §1), right after the splash: the Nervo logo,
/// a carousel of 3 scenes that advance on their own every 4 s and can be swiped, then
/// "Créer un compte" and "Se connecter". On the first launch the Measurement consent sheet opens
/// over it (§8). The app shell passes the account screen (ADR-007 rule 5), with its way back.
struct WelcomeView<Account: View>: View {
    let consent: MeasurementConsentStore
    /// `false` while the splash covers the screen: the carousel and the consent sheet wait.
    var isRevealed = true
    /// The account screen for an entry, and the action back to the Welcome.
    @ViewBuilder let account: (WelcomeEntry, _ back: @escaping () -> Void) -> Account

    /// The account screen opened from here, if any.
    @State private var entry: WelcomeEntry?

    var body: some View {
        ZStack {
            if let entry {
                account(entry) {
                    withAnimation(.snappy) { self.entry = nil }
                }
                .transition(.move(edge: .trailing))
            } else {
                WelcomeContent(isRevealed: isRevealed) { entry in
                    withAnimation(.snappy) { self.entry = entry }
                }
                .transition(.move(edge: .leading))
            }
        }
        .measurementConsentSheet(consent)
        .task(id: isRevealed) {
            guard isRevealed else { return }
            await consent.askIfNeeded()
        }
    }
}

private struct WelcomeContent: View {
    let isRevealed: Bool
    let open: (WelcomeEntry) -> Void

    @State private var page = WelcomeScene.liveActivity

    var body: some View {
        VStack(spacing: 0) {
            NervoWordmark()
                .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(WelcomeScene.allCases) { scene in
                    VStack(spacing: 28) {
                        scene.illustration
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .padding(.horizontal, Theme.spacing)
                            .padding(.top, 12)
                        Text(scene.title)
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.4)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }
                    .tag(scene)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("welcome.carousel")

            pageIndicator
                .padding(.vertical, 18)

            VStack(spacing: 6) {
                Button("Créer un compte") { open(.createAccount) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("welcome.createAccount")
                Button("Se connecter") { open(.signIn) }
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("welcome.signIn")
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .sensoryFeedback(.selection, trigger: page)
        // Each page change (on its own or swiped) restarts the 4 s before the next one.
        .task(id: [page.rawValue, isRevealed ? 1 : 0]) {
            guard isRevealed else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { page = page.next }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(WelcomeScene.allCases) { scene in
                Capsule()
                    .fill(scene == page ? Theme.accent : Color(.systemGray4))
                    .frame(width: scene == page ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page.rawValue + 1) sur \(WelcomeScene.allCases.count)")
    }
}

private extension WelcomeScene {
    /// The carousel loops back to the first scene.
    var next: WelcomeScene {
        WelcomeScene(rawValue: (rawValue + 1) % WelcomeScene.allCases.count) ?? .liveActivity
    }
}

/// The Nervo logo: the N on its orange tile, then the name.
private struct NervoWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            NervoMark()
                .stroke(.white, style: NervoMark.strokeStyle(forSide: 22))
                .frame(width: 22, height: 22)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
            Text("Nervo")
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nervo")
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview {
    WelcomeView(
        consent: MeasurementConsentStore(
            preferences: UserDefaultsMeasurementConsentPreferences(defaults: UserDefaults(suiteName: "preview.welcome")!),
            analytics: NoAnalyticsClient(),
            signedInUserID: { nil }
        )
    ) { entry, back in
        VStack(spacing: 16) {
            Text(entry == .createAccount ? "Créer un compte" : "Se connecter")
            Button("Retour", action: back)
        }
    }
}
#endif
