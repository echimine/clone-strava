import Foundation

/// The words of creating a Segment and of Plus › « Segments » (ADR-039 §15), « tu » as Strava.
enum SegmentMessages {
    static let connectionRequired = "Connexion requise"
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
    static let loadFailed = "Impossible de charger tes Segments."

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

    /// "8,0 %".
    static func grade(_ percent: Double) -> String {
        "\(percent.formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) %"
    }
}
