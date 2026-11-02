#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway, never merged to main (wayfinder ticket « Contenu des écrans
// d'Onboarding », #111). Question: what exactly do the Onboarding screens say and ask?
// Three structurally different variants of the same content, switchable from the floating pill
// at the bottom: A « Strava fidèle » (one question per screen), B « 3 étapes » (grouped native
// forms), C « Conversation » (one scrolling thread). Answers live in memory only.
// Launch: `xcrun simctl launch booted <bundle id> -prototypeOnboarding`.

// MARK: - Content under review (shared by the three variants)

enum ProtoCopy {
    static let minimumAge = 15

    static let nameTitle = "Comment vous appelez-vous ?"
    static let nameSubtitle = "C'est ainsi que vos amis vous trouveront sur Nervo."
    static let nameFootnote = "Votre nom est visible sur votre profil."

    static let birthTitle = "Quelle est votre date de naissance ?"
    static let birthSubtitle = "Elle sert à analyser vos performances et à protéger les plus jeunes."
    static let birthFootnote = "Ni votre date de naissance ni votre âge n'apparaissent sur votre profil."
    static let tooYoung = "Nervo est réservé aux personnes de \(minimumAge) ans ou plus."

    static let genderTitle = "Quel est votre genre ?"
    static let genderSubtitle = "Il sert à vous placer dans les bons classements."
    static let genderFootnote = "Votre genre n'apparaît pas sur votre profil."

    static let sportsTitle = "Quels sports pratiquez-vous ?"
    static let sportsSubtitle = "Choisissez-en autant que vous voulez. Vous pourrez enregistrer n'importe lequel ensuite."

    static let goalsTitle = "Qu'attendez-vous de Nervo ?"
    static let goalsSubtitle = "Choisissez-en autant que vous voulez."

    static let levelTitle = "Où en êtes-vous dans votre pratique ?"
    static let levelSubtitle = "Nervo accueille tous les niveaux, du grand débutant à l'athlète pro."
}

enum ProtoGender: String, CaseIterable, Identifiable {
    case man = "Homme", woman = "Femme", nonBinary = "Non-binaire", undisclosed = "Je préfère ne pas le dire"
    var id: Self { self }
}

enum ProtoGoal: String, CaseIterable, Identifiable {
    case compete = "Me mesurer aux autres"
    case explore = "Découvrir de nouveaux parcours"
    case health = "Prendre soin de ma santé"
    case people = "Rejoindre d'autres sportifs"
    case event = "Préparer une course ou un objectif"
    case habit = "Prendre l'habitude de bouger"
    var id: Self { self }
    /// Shown under the goal once selected (Strava reveals it the same way).
    var detail: String {
        switch self {
        case .compete: "Comparez vos temps sur les segments et grimpez dans les classements."
        case .explore: "Trouvez des itinéraires près de chez vous ou là où vous partez."
        case .health: "Suivez votre activité semaine après semaine."
        case .people: "Suivez vos amis et encouragez-les avec des kudos."
        case .event: "Suivez vos progrès et analysez chaque activité."
        case .habit: "Bougez régulièrement et voyez vos efforts s'accumuler."
        }
    }
}

enum ProtoLevel: String, CaseIterable, Identifiable {
    case beginner = "Débutant", intermediate = "Intermédiaire", advanced = "Confirmé", pro = "Professionnel"
    var id: Self { self }
    var detail: String {
        switch self {
        case .beginner: "Je débute ou je reprends le sport."
        case .intermediate: "Je fais des efforts faciles à modérés."
        case .advanced: "J'aime me dépasser sur des efforts difficiles."
        case .pro: "Je suis athlète professionnel."
        }
    }
}

/// The active sports of `sports.sport_type`, so the Onboarding never offers a sport that
/// cannot be recorded.
let protoSports = SportType.active

// MARK: - Answers (in memory)

@Observable
final class ProtoAnswers {
    var firstName = ""
    var lastName = ""
    var birthDate: Date?
    var gender: ProtoGender?
    var sports: [SportType] = []
    var goals: Set<ProtoGoal> = []
    var level: ProtoLevel?
    /// What happened on the Paywall (#110), shown in the state sheet.
    var paywallEvents: [String] = []
    /// Measurement consent sheet on the Welcome (#113, #116): nil until answered.
    var measurementConsent: String?

    var nameIsValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var age: Int? {
        birthDate.flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year }
    }
    var birthIsValid: Bool { (age ?? 0) >= ProtoCopy.minimumAge }
    var isTooYoung: Bool { birthDate != nil && !birthIsValid }

    /// Answers of a made-up athlete, when the prototype opens past the questions (`-protoStage`).
    static func demo() -> ProtoAnswers {
        let answers = ProtoAnswers()
        answers.firstName = "Camille"
        answers.lastName = "Martin"
        answers.birthDate = Calendar.current.date(byAdding: .year, value: -32, to: .now)
        answers.gender = .woman
        answers.sports = [.run, .ride]
        answers.goals = [.event, .explore]
        answers.level = .intermediate
        return answers
    }

    func toggle(_ sport: SportType) {
        if let index = sports.firstIndex(of: sport) { sports.remove(at: index) } else { sports.append(sport) }
    }
    func toggle(_ goal: ProtoGoal) {
        if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
    }

    var summary: [(String, String)] {
        [
            ("Prénom", firstName.isEmpty ? "—" : firstName),
            ("Nom", lastName.isEmpty ? "—" : lastName),
            ("Naissance", birthDate.map { "\($0.formatted(date: .numeric, time: .omitted)) (\(age ?? 0) ans)" } ?? "—"),
            ("Genre", gender?.rawValue ?? "—"),
            ("Sports", sports.isEmpty ? "—" : sports.map(ActivityFormatters.sportLabel).joined(separator: ", ")),
            ("Objectifs", goals.isEmpty ? "—" : ProtoGoal.allCases.filter(goals.contains).map(\.rawValue).joined(separator: ", ")),
            ("Niveau", level?.rawValue ?? "—"),
            ("Mesure d'audience", measurementConsent ?? "—"),
            ("Paywall", paywallEvents.last ?? "—"),
        ]
    }
}

// MARK: - Host: variant switcher, state, recap

struct OnboardingPrototypeView: View {
    static let launchArgument = "-prototypeOnboarding"

    enum Variant: String, CaseIterable {
        case a = "A", b = "B", c = "C"
        var name: String {
            switch self {
            case .a: "Strava fidèle"
            case .b: "3 étapes"
            case .c: "Conversation"
            }
        }
    }

    @AppStorage("prototype.onboarding.variant") private var variantKey = Variant.a.rawValue
    @State private var answers = UserDefaults.standard.string(forKey: "protoStage").map { ["account", "paywall", "notifications"].contains($0) } == true
        ? ProtoAnswers.demo() : ProtoAnswers()
    /// Questions, then « ce que vous pouvez faire », then the personalised loading screen.
    /// Then the account (stub) and the Paywall (#110), then the notifications permission (stub).
    enum Stage: String { case welcome, questions, showcase, personalizing, account, paywall, notifications }

    /// `-protoStage showcase` (or `personalizing`) opens straight on that screen.
    @State private var stage = Stage(rawValue: UserDefaults.standard.string(forKey: "protoStage") ?? "") ?? .welcome
    @State private var showsState = false
    @State private var runID = UUID()
    @AppStorage("prototype.paywall.variant") private var paywallKey = ProtoPaywallVariant.a.rawValue
    @State private var offeringMode = ProtoOfferingMode.ok
    @State private var paywallRunID = UUID()
    @AppStorage("prototype.welcome.variant") private var welcomeKey = ProtoWelcomeVariant.a.rawValue
    @State private var welcomeRunID = UUID()

    private var welcomeVariant: ProtoWelcomeVariant { ProtoWelcomeVariant(rawValue: welcomeKey) ?? .a }

    private var paywallVariant: ProtoPaywallVariant { ProtoPaywallVariant(rawValue: paywallKey) ?? .a }

    private var variant: Variant { Variant(rawValue: variantKey) ?? .a }

    var body: some View {
        Group {
            switch stage {
            case .welcome:
                ProtoWelcome(variant: welcomeVariant, answers: answers, actions: ProtoWelcomeActions(
                    createAccount: advance,
                    // « Se connecter » skips the Onboarding (map #105).
                    signIn: { withAnimation(.easeInOut(duration: 0.4)) { stage = .account } }))
                .id(welcomeRunID)
            case .questions:
                switch variant {
                case .a: ProtoVariantA(answers: answers) { advance() }
                case .b: ProtoVariantB(answers: answers) { advance() }
                case .c: ProtoVariantC(answers: answers) { advance() }
                }
            case .showcase: ProtoShowcase(answers: answers) { advance() }
            case .personalizing: ProtoPersonalizing(answers: answers) { advance() }
            case .account: ProtoAccountStub(signedIn: advance, restart: restart)
            case .paywall:
                ProtoPaywall(answers: answers,
                             service: ProtoUnwiredSubscriptionService(mode: offeringMode, layout: paywallVariant)) { outcome in
                    answers.paywallEvents.append(outcome)
                    advance()
                }
                .id(paywallRunID)
            case .notifications: ProtoNotificationsStub(answers: answers, backToPaywall: backToPaywall, restart: restart)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 1.02)))
        .id(runID)
        .safeAreaInset(edge: .bottom) { switcher }
        .sheet(isPresented: $showsState) {
            NavigationStack {
                List(answers.summary, id: \.0) { LabeledContent($0.0, value: $0.1) }
                    .navigationTitle("Réponses d'onboarding")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }

    private var switcher: some View {
        HStack(spacing: 14) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
            Group {
                if stage == .welcome {
                    Text("\(welcomeVariant.rawValue) · \(welcomeVariant.name)")
                } else if stage == .paywall {
                    Text("\(paywallVariant.rawValue) · \(paywallVariant.name)")
                } else {
                    Text("\(variant.rawValue) · \(variant.name)")
                }
            }
            .monospaced().frame(minWidth: 130)
            Button { cycle(1) } label: { Image(systemName: "chevron.right") }
            Divider().frame(height: 16).overlay(.white.opacity(0.4))
            if stage == .paywall {
                // Simulates RevenueCat being slow or down (once wired).
                Button { cycleOfferingMode() } label: {
                    Image(systemName: offeringMode == .ok ? "wifi" : offeringMode == .slow ? "tortoise.fill" : "wifi.slash")
                }
            }
            Button(action: advance) { Image(systemName: "forward.end.fill") }
            Button { showsState = true } label: { Image(systemName: "list.bullet.rectangle") }
            Button(action: restart) { Image(systemName: "arrow.counterclockwise") }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Capsule().fill(.purple.gradient))
        .shadow(radius: 6, y: 2)
        .padding(.bottom, 2)
    }

    /// Next stage; also the ⏭ of the pill, to review the end screens without answering.
    private func advance() {
        let next: Stage = switch stage {
        case .welcome: .questions
        case .questions: .showcase
        case .showcase: .personalizing
        case .personalizing: .account
        case .account: .paywall
        case .paywall, .notifications: .notifications
        }
        withAnimation(.easeInOut(duration: 0.4)) { stage = next }
    }

    private func cycle(_ step: Int) {
        if stage == .welcome {
            let all = ProtoWelcomeVariant.allCases
            let index = (all.firstIndex(of: welcomeVariant)! + step + all.count) % all.count
            welcomeKey = all[index].rawValue
            welcomeRunID = UUID()
            return
        }
        if stage == .paywall {
            let all = ProtoPaywallVariant.allCases
            let index = (all.firstIndex(of: paywallVariant)! + step + all.count) % all.count
            paywallKey = all[index].rawValue
            paywallRunID = UUID()
            return
        }
        let all = Variant.allCases
        let index = (all.firstIndex(of: variant)! + step + all.count) % all.count
        variantKey = all[index].rawValue
        stage = .questions
        runID = UUID()
    }

    /// Reloads the Paywall with the next stub behaviour (OK → slow → unavailable).
    private func cycleOfferingMode() {
        let all = ProtoOfferingMode.allCases
        offeringMode = all[(all.firstIndex(of: offeringMode)! + 1) % all.count]
        paywallRunID = UUID()
    }

    private func backToPaywall() {
        offeringMode = .ok
        paywallRunID = UUID()
        withAnimation(.easeInOut(duration: 0.4)) { stage = .paywall }
    }

    /// A fresh first launch: splash, Welcome, Measurement consent sheet.
    private func restart() {
        answers = ProtoAnswers()
        stage = .welcome
        welcomeRunID = UUID()
        runID = UUID()
    }
}

// MARK: - Shared controls

struct ProtoPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white)
                .background(Capsule().fill(Theme.accent.opacity(isEnabled ? 1 : 0.35)))
                .contentShape(Capsule())
        }
        .buttonStyle(ProtoPressStyle())
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}

/// Slight shrink while pressed, so taps feel physical.
struct ProtoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A full-width choice, inverted when selected (Strava's gender, goals and level rows).
/// `revealsDetail`: the detail only shows once selected (goals); otherwise always (level).
struct ProtoChoiceRow: View {
    let title: String
    var detail: String?
    var revealsDetail = false
    let isSelected: Bool
    let action: () -> Void

    private var showsDetail: Bool { detail != nil && (!revealsDetail || isSelected) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                if showsDetail, let detail {
                    Text(detail).font(.subheadline)
                        .foregroundStyle(isSelected ? Color(.systemBackground).opacity(0.8) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 16)
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.primary : Color(.secondarySystemBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ProtoPressStyle())
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ProtoSportTile: View {
    let sport: SportType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: ActivityFormatters.sportSymbol(sport)).font(.title2)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color(.systemGray3))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(ActivityFormatters.sportLabel(sport)).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.primary : Color(.secondarySystemBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ProtoPressStyle())
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Default position of the birth date wheels: 30 years ago, so most people scroll little.
let protoDefaultBirthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
#endif
