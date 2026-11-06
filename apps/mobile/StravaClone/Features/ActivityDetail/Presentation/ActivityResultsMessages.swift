import Foundation

/// French texts of « Résultats » (ADR-039 §1, §15), as Strava words them.
enum ActivityResultsMessages {
    static let title = "Résultats"
    static let bestEfforts = "Meilleurs efforts"
    static let segments = "Segments"
    static let performances = "Performances"
    static let showAll = "Afficher tous les résultats"
    static let matching = "Recherche des Segments de cette Activité…"
    static let halfMarathon = "SEMI-MARATHON"
    static let marathon = "MARATHON"
    static let localLegend = "Légende locale"

    // MARK: Retirer un temps

    static let remove = "Retirer ce temps de mes meilleurs efforts"
    static let removeConfirmTitle = "Retirer ce temps ?"
    static let removeConfirm = "Retirer"
    static let removeMessage = "Ce temps ne comptera plus dans tes meilleurs efforts ni pour tes médailles. C'est définitif."
    static let removeHint = "Appui long sur un temps pour le retirer de tes meilleurs efforts."
    static let removed = "Temps retiré de tes meilleurs efforts"

    /// Under a Best effort: « Nouveau record absolu ! », « Nouveau 2e record absolu ! »…
    static func bestEffortPhrase(_ medal: Medal) -> String {
        switch medal {
        case .gold: "Nouveau record absolu !"
        case .silver: "Nouveau 2e record absolu !"
        case .bronze: "Nouveau 3e record absolu !"
        }
    }

    /// Under a Segment: « Record personnel », « 2e meilleur temps »…, « · 1er passage » for a
    /// first Effort.
    static func segmentPhrase(_ medal: Medal, firstPass: Bool) -> String {
        let phrase = segmentMedal(medal)
        return firstPass ? "\(phrase) · 1er passage" : phrase
    }

    /// A Segment's Medal, also on the map's labels.
    static func segmentMedal(_ medal: Medal) -> String {
        switch medal {
        case .gold: "Record personnel"
        case .silver: "2e meilleur temps"
        case .bronze: "3e meilleur temps"
        }
    }

    /// « Meilleurs efforts · piscine, bassin de 25 m ».
    static func bestEffortsHeader(poolLength: Distance?) -> String {
        guard let poolLength else { return bestEfforts }
        return "\(bestEfforts) · piscine, bassin de \(poolLengthText(poolLength))"
    }

    /// « 25 m », or « 25 yd » for a pool in yards.
    static func poolLengthText(_ length: Distance) -> String {
        let yards = length.meters / 0.9144
        if abs(length.meters - length.meters.rounded()) > 0.01, abs(yards - yards.rounded()) < 0.01 {
            return "\(Int(yards.rounded())) yd"
        }
        return "\(Int(length.meters.rounded())) m"
    }

    /// An Activity that is not public: its Efforts do not count on the Leaderboard. Only its
    /// author reads « tes abonnés »; anyone else reads a neutral note.
    static func notOnLeaderboard(_ visibility: ActivityVisibility, viewerIsAuthor: Bool) -> String? {
        switch visibility {
        case .public: nil
        case .followers where viewerIsAuthor: "Activité visible par tes abonnés : ses Efforts ne comptent pas au Classement."
        case .followers: "Activité réservée aux abonnés : ses Efforts ne comptent pas au Classement."
        case .private: "Activité privée : ses Efforts ne comptent pas au Classement."
        }
    }
}
