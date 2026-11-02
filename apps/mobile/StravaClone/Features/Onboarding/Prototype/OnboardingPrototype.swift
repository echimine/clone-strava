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

    var nameIsValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var age: Int? {
        birthDate.flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year }
    }
    var birthIsValid: Bool { (age ?? 0) >= ProtoCopy.minimumAge }
    var isTooYoung: Bool { birthDate != nil && !birthIsValid }

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
    @State private var answers = ProtoAnswers()
    @State private var finished = false
    @State private var showsState = false
    @State private var runID = UUID()

    private var variant: Variant { Variant(rawValue: variantKey) ?? .a }

    var body: some View {
        Group {
            if finished {
                ProtoRecap(answers: answers, restart: restart)
            } else {
                switch variant {
                case .a: ProtoVariantA(answers: answers) { finished = true }
                case .b: ProtoVariantB(answers: answers) { finished = true }
                case .c: ProtoVariantC(answers: answers) { finished = true }
                }
            }
        }
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
            Text("\(variant.rawValue) · \(variant.name)").monospaced().frame(minWidth: 150)
            Button { cycle(1) } label: { Image(systemName: "chevron.right") }
            Divider().frame(height: 16).overlay(.white.opacity(0.4))
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

    private func cycle(_ step: Int) {
        let all = Variant.allCases
        let index = (all.firstIndex(of: variant)! + step + all.count) % all.count
        variantKey = all[index].rawValue
        finished = false
        runID = UUID()
    }

    private func restart() {
        answers = ProtoAnswers()
        finished = false
        runID = UUID()
    }
}

private struct ProtoRecap: View {
    let answers: ProtoAnswers
    let restart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fin de l'Onboarding").font(.largeTitle.bold())
            Text("Réponses gardées sur le téléphone. Écran suivant : création du compte (Google ou email + code).")
                .foregroundStyle(.secondary)
            List(answers.summary, id: \.0) { LabeledContent($0.0, value: $0.1) }
                .listStyle(.insetGrouped)
            ProtoPrimaryButton(title: "Recommencer", isEnabled: true, action: restart)
        }
        .padding(Theme.spacing)
    }
}

// MARK: - Shared controls

struct ProtoPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(Capsule().fill(Theme.accent.opacity(isEnabled ? 1 : 0.35)))
        }
        .disabled(!isEnabled)
    }
}

/// A full-width choice, black when selected (Strava's gender, goals and level rows).
struct ProtoChoiceRow: View {
    let title: String
    var detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail { Text(detail).font(.footnote) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.primary : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

struct ProtoSportTile: View {
    let sport: SportType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: ActivityFormatters.sportSymbol(sport)).font(.title2)
                Text(ActivityFormatters.sportLabel(sport)).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .padding(14)
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.primary : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

/// Default position of the birth date wheels: 30 years ago, so most people scroll little.
let protoDefaultBirthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
#endif
