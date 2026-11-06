import Foundation

/// French copy of Segments (ADR-039 §15), Strava's wording, « tu »: creating a Segment, Plus ›
/// « Segments », a Segment's sheet and its Leaderboard.
enum SegmentMessages {
    // MARK: Creating a Segment and Plus › « Segments » (#249)

    static let placeStartAndFinish = "Place un départ et une arrivée sur la carte."
    static let unavailable = "Mesure indisponible pour le moment. Réessaie."
    static let oneSportOnly = "Un Segment n'a qu'un sport : seules les Activités de ce sport y sont classées."
    static let createFailed = "Le Segment n'a pas pu être créé. Réessaie."
    static let duplicateTitle = "Ce Segment existe déjà"
    static let quotaReached = "Tu as créé 10 Segments ces dernières 24 h. Réessaie un peu plus tard."
    static let nameTooShort = "3 caractères au moins."
    static let nameTooLong = "60 caractères au plus."
    static let publicNotice = "Un Segment est public : tous les athlètes qui passent dessus y sont classés. "
        + "Ton nom n'est jamais affiché comme créateur. Le tracé ne pourra plus être modifié."
    static let searchingEfforts = "On cherche tes passages… Le classement se remplit dans quelques minutes."
    static let mySegmentsTitle = "Segments"
    static let emptyTitle = "Aucun Segment"
    static let emptyDescription = "Les Segments que tu crées ou mets en favori apparaissent ici."
    static let mySegmentsLoadFailed = "Impossible de charger tes Segments."

    /// The minimum of a sport, in the sport list.
    static func minimum(_ sport: SegmentSport) -> String {
        sport == .ride ? "500 m min." : "200 m min."
    }

    static func violation(_ violation: SegmentRuleViolation, sport: SegmentSport) -> String {
        switch violation {
        case .tooShort: sport == .ride ? "Trop court : au moins 500 m à vélo." : "Trop court : au moins 200 m."
        case .tooLong: "Trop long : 50 km au plus."
        case .loop: "Le départ et l'arrivée doivent être à plus de 100 m l'un de l'autre."
        }
    }

    static func duplicate(_ existing: SegmentRef) -> String {
        "« \(existing.name) » suit le même tracé : tes passages y sont déjà comptés."
    }

    // MARK: A Segment's sheet and Leaderboard (#251)

    static let gone = "Ce Segment n'est plus disponible"
    static let goneDetail = "Il a été supprimé."
    static let loadFailed = "Impossible d'afficher ce Segment."
    static let retry = "Réessayer"
    static let connectionRequired = "Connexion requise"
    static let serverFailed = "Le serveur n'a pas répondu. Réessaie."
    static let sessionExpired = "Votre session a expiré, reconnectez-vous."

    static let verified = "Segment vérifié"
    static let distance = "Distance"
    static let elevationGain = "Dénivelé +"
    static let averageGrade = "Pente moy."
    static let category = "Catégorie"
    static let historyMatching = "Recherche des Efforts passés sur ce Segment… Le Classement se remplit au fur et à mesure."
    static let attribution = "Données © OpenStreetMap"

    static let myEfforts = "Mes efforts"
    static let myRecord = "Mon record"
    static let myRank = "Mon rang"
    static let privateActivity = "Activité privée"
    static let notStanding = "Privée · hors Classement"
    static let noEffortTitle = "Pas encore d'Effort ici"
    static let noEffortDetail = "Passe sur ce Segment pendant une Activité : ton temps, ta Médaille et ton rang s'afficheront ici."

    static let localLegend = "Légende locale"
    static let noLocalLegend = "Personne n'est passé ici ces 90 derniers jours : le premier devient Légende locale."
    static let you = "Toi"

    static let leaderboard = "Classement"
    static let seeLeaderboard = "Voir le classement"
    static let notInFilter = "Tu n'apparais pas dans ce filtre"
    static let nobodyInFilter = "Personne dans ce filtre."
    static let premiumInsertTitle = "Voir le classement complet avec Premium"

    static let report = "Signaler ce Segment"
    static let rename = "Renommer"
    static let renameTitle = "Renommer le Segment"
    static let renamePlaceholder = "Nom du Segment"
    static let renameFooter = "De 3 à 60 caractères."
    static let save = "Enregistrer"
    static let cancel = "Annuler"
    static let delete = "Supprimer"
    static let deleteTitle = "Supprimer ce Segment ?"
    static let deleteMessage = "Il disparaît pour tout le monde, avec ses Efforts. C'est définitif."
    static let deleteRefusedTitle = "Suppression impossible"
    static let deleteRefusedMessage = "D'autres athlètes ont déjà un Effort sur ce Segment : il reste en place. Tu peux toujours le renommer."
    static let ok = "OK"
    static let addFavorite = "Ajouter aux favoris"
    static let removeFavorite = "Retirer des favoris"

    /// ADR-039 §5: a name of 3 to 60 characters once trimmed.
    static func isValidName(_ name: String) -> Bool {
        (3...60).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    static func category(_ category: ClimbCategory?) -> String {
        category?.label ?? "—"
    }

    static func grade(_ percent: Double?) -> String {
        guard let percent else { return "—" }
        return "\(percent.formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) %"
    }

    /// « 4:05 », « 1:02:30 »: an Effort's elapsed time.
    static func time(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let rest = seconds % 60
        return hours > 0
            ? "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", rest))"
            : "\(minutes):\(String(format: "%02d", rest))"
    }

    /// « 12 sept. 2026 ».
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(ActivityFormatters.locale))
    }

    static func rank(_ rank: Int) -> String {
        rank == 1 ? "1er" : "\(rank)e"
    }

    static func legendEfforts(_ count: Int) -> String {
        "\(count) \(count > 1 ? "Efforts" : "Effort") ces 90 derniers jours"
    }

    /// « Toi : n Efforts. Encore k pour devenir Légende locale. »
    static func toTakeTheLegend(mine: Int, missing: Int) -> String {
        "Toi : \(mine) \(mine > 1 ? "Efforts" : "Effort"). Encore \(missing) pour devenir Légende locale."
    }

    static func meLabel(_ name: String) -> String { "\(name) (toi)" }

    static func premiumInsertDetail(athletes: Int) -> String {
        "\(athletes) \(athletes > 1 ? "athlètes" : "athlète"), filtres par sexe, période, âge, poids et Abonnements"
    }

    static func gender(_ gender: LeaderboardGender) -> String {
        switch gender {
        case .all: "Tous"
        case .male: "Hommes"
        case .female: "Femmes"
        }
    }

    static func period(_ period: LeaderboardPeriod) -> String {
        switch period {
        case .today: "Aujourd'hui"
        case .week: "Cette semaine"
        case .month: "Ce mois-ci"
        case .year: "Cette année"
        }
    }

    static let following = "Abonnements"
    static let age = "Âge"
    static let weight = "Poids"
    static let removeFilter = "Retirer"

    static func ageBand(_ band: String) -> String {
        switch band {
        case "0-19": "19 ans et moins"
        case "75+": "75 ans et plus"
        default: "\(band.replacingOccurrences(of: "-", with: " à ")) ans"
        }
    }

    static func weightBand(_ band: String) -> String {
        switch band {
        case "0-54": "54 kg et moins"
        case "115+": "115 kg et plus"
        default: "\(band.replacingOccurrences(of: "-", with: " à ")) kg"
        }
    }

    static func message(for error: SegmentError) -> String {
        switch error {
        case .offline: connectionRequired
        case .unauthorized: sessionExpired
        case .notFound: gone
        case .premiumRequired: premiumInsertTitle
        case .hasOtherEfforts: deleteRefusedMessage
        case .invalid, .server, .zoneTooLarge, .duplicate, .quota, .rejected: serverFailed
        case .network: connectionRequired
        }
    }
}
