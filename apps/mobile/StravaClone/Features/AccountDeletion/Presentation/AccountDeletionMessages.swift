import Foundation

/// French copy of « Supprimer mon compte » (ADR-038 §13).
enum AccountDeletionMessages {
    static let button = "Supprimer mon compte"
    static let title = "Supprimer mon compte"
    static let erasedHeader = "Ce qui sera effacé"
    static let erased = [
        "Vos Activités, leurs tracés et leurs Médias",
        "Vos commentaires et kudos, y compris chez les autres",
        "Vos abonnés et vos abonnements",
        "Votre profil, vos Itinéraires et votre photo",
    ]
    static let erasedFooter = "La suppression est immédiate et définitive. Vos Signalements restent, sans votre nom ni votre note."
    static let lostHeader = "Sur ce téléphone"
    static let premiumHeader = "Abonnement Premium"
    static let premiumWarning = "Votre abonnement continue d'être facturé par Apple."
    static let manageSubscription = "Gérer mon abonnement"
    static let sendCode = "Recevoir un code"
    static let codeHeader = "Code de connexion"
    static let codeFooter = "Saisissez le code envoyé à votre adresse e-mail."
    static let codePlaceholder = "123456"
    static let resendCode = "Recevoir un nouveau code"
    static let confirm = "Supprimer définitivement"
    static let deleted = "Compte supprimé"

    static let administrator = "Un administrateur ne peut pas supprimer son compte"
    static let invalidCode = "Code incorrect. Vérifiez-le ou demandez-en un nouveau."
    static let expiredCode = "Ce code a expiré. Demandez-en un nouveau."
    static let offline = "Vous êtes hors ligne. La suppression du compte demande une connexion."
    static let failure = "La suppression n'a pas abouti. Réessayez dans un instant."

    static func message(for error: AccountDeletionError) -> String {
        switch error {
        case .administrator: administrator
        case .invalidCode: invalidCode
        case .expiredCode: expiredCode
        case .offline: offline
        case .network, .unauthorized, .server: failure
        }
    }
}
