import Foundation

// What the Onboarding screens say (ADR-035 §1, §9; prototype variant A, #111).

extension OnboardingStep {
    /// The six questions, which the progress bar counts.
    static let questions: [OnboardingStep] = [.name, .birthDate, .gender, .sports, .goals, .level]

    /// `firstName` greets the person on the birth date screen.
    func title(firstName: String) -> String {
        switch self {
        case .name: "Comment vous appelez-vous ?"
        case .birthDate:
            firstName.isEmpty
                ? "Quelle est votre date de naissance ?"
                : "Bienvenue, \(firstName) ! Quelle est votre date de naissance ?"
        case .gender: "Quel est votre genre ?"
        case .sports: "Quels sports pratiquez-vous ?"
        case .goals: "Qu'attendez-vous de Nervo ?"
        case .level: "Où en êtes-vous dans votre pratique ?"
        case .showcase, .personalizing, .account: ""
        }
    }

    /// The line under the title; the birth date screen has its mention under the field instead.
    var subtitle: String? {
        switch self {
        case .name: "C'est ainsi que vos amis vous trouveront sur Nervo."
        case .gender: "Il sert à vous placer dans les bons classements."
        case .sports: "Choisissez-en autant que vous voulez. Vous pourrez enregistrer n'importe lequel ensuite."
        case .goals: "Choisissez-en autant que vous voulez."
        case .level: "Nervo accueille tous les niveaux, du grand débutant à l'athlète pro."
        case .birthDate, .showcase, .personalizing, .account: nil
        }
    }
}

enum OnboardingCopy {
    static let nameMention = "Votre nom est visible sur votre profil."
    static let birthDateMention = "Sert à vérifier votre âge. Elle n'apparaît jamais sur votre profil."
    static let genderMention = "Visible par vous seul."
    static let tooYoung = "Nervo est réservé aux personnes de \(OnboardingAnswers.minimumAge) ans ou plus."
}

extension Gender {
    var label: String {
        switch self {
        case .male: "Homme"
        case .female: "Femme"
        case .nonBinary: "Non-binaire"
        case .undisclosed: "Je préfère ne pas le dire"
        }
    }
}

extension Goal {
    var label: String {
        switch self {
        case .compete: "Me mesurer aux autres"
        case .discoverRoutes: "Découvrir de nouveaux parcours"
        case .health: "Prendre soin de ma santé"
        case .meetAthletes: "Rejoindre d'autres sportifs"
        case .trainForEvent: "Préparer une course ou un objectif"
        case .buildHabit: "Prendre l'habitude de bouger"
        }
    }

    /// Shown under the goal once picked.
    var detail: String {
        switch self {
        case .compete: "Comparez vos temps sur les segments et grimpez dans les classements."
        case .discoverRoutes: "Trouvez des itinéraires près de chez vous ou là où vous partez."
        case .health: "Suivez votre activité semaine après semaine."
        case .meetAthletes: "Suivez vos amis et encouragez-les avec des kudos."
        case .trainForEvent: "Suivez vos progrès et analysez chaque activité."
        case .buildHabit: "Bougez régulièrement et voyez vos efforts s'accumuler."
        }
    }
}

extension AthleteLevel {
    var label: String {
        switch self {
        case .beginner: "Débutant"
        case .intermediate: "Intermédiaire"
        case .advanced: "Confirmé"
        case .professional: "Professionnel"
        }
    }

    var detail: String {
        switch self {
        case .beginner: "Je débute ou je reprends le sport."
        case .intermediate: "Je fais des efforts faciles à modérés."
        case .advanced: "J'aime me dépasser sur des efforts difficiles."
        case .professional: "Je suis athlète professionnel."
        }
    }
}
