import SwiftUI

/// The Onboarding (ADR-035 §1), opened by "Créer un compte" on the Welcome: the six questions,
/// "Voici ce qui vous attend", the personalised loading, then the account screen in creation
/// mode with "Prénom Nom". It opens on the screen saved in the draft (§5). The account screen
/// belongs to the Auth feature: the App layer builds it (ADR-007 rule 5), from the account's
/// name and the back action to the last screen.
struct OnboardingView<AccountScreen: View>: View {
    @State private var store: OnboardingStore
    private let accountScreen: (_ name: String, _ back: @escaping () -> Void) -> AccountScreen

    /// The draft is read before anything shows, so a resumed Onboarding does not flash its first screen.
    @State private var isLoaded = false
    /// Which way the screens slide: forward to the left, back to the right.
    @State private var isForward = true

    init(
        store: OnboardingStore,
        @ViewBuilder accountScreen: @escaping (_ name: String, _ back: @escaping () -> Void) -> AccountScreen
    ) {
        _store = State(initialValue: store)
        self.accountScreen = accountScreen
    }

    var body: some View {
        ZStack {
            if isLoaded {
                screen
                    .id(Screen(store.step))
                    .transition(.slide(forward: isForward))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .animation(.snappy(duration: 0.35), value: Screen(store.step))
        .sensoryFeedback(.impact(weight: .light), trigger: store.step)
        .task {
            await store.load()
            isLoaded = true
        }
    }

    @ViewBuilder private var screen: some View {
        switch store.step {
        case .name, .birthDate, .gender, .sports, .goals, .level:
            OnboardingQuestionsView(store: store, isForward: isForward, next: next, back: back)
        case .showcase:
            OnboardingShowcase(firstName: store.firstName, sport: store.answers.sports.first ?? .run, finish: next)
        case .personalizing:
            OnboardingPersonalizing(answers: store.answers, firstName: store.firstName, createAccount: next)
        case .account:
            accountScreen(store.accountName, back)
        }
    }

    private func next() {
        isForward = true
        Task { await store.next() }
    }

    private func back() {
        isForward = false
        Task { await store.back() }
    }

    /// What slides as a whole: the questions slide inside one screen, under a fixed header.
    private enum Screen: Hashable {
        case questions, showcase, personalizing, account

        init(_ step: OnboardingStep) {
            switch step {
            case .name, .birthDate, .gender, .sports, .goals, .level: self = .questions
            case .showcase: self = .showcase
            case .personalizing: self = .personalizing
            case .account: self = .account
            }
        }
    }
}

extension AnyTransition {
    /// The directional slide between Onboarding screens.
    static func slide(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

#if DEBUG
#Preview {
    OnboardingView(
        store: OnboardingStore(drafts: GRDBOnboardingDraftRepository(database: try! AppDatabase.inMemory()))
    ) { name, _ in
        Text("Compte de \(name)")
    }
}
#endif
