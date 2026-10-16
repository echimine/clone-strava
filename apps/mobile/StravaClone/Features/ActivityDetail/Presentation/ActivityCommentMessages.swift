import Foundation

/// French strings of the comment thread (ADR-034 §6).
enum ActivityCommentMessages {
    static let title = "Commentaires"
    static let previous = "Voir les commentaires précédents"
    static let placeholder = "Ajouter un commentaire…"
    static let send = "Envoyer"
    static let sending = "Envoi…"
    static let failed = "Échec · Réessayer"
    static let edited = "modifié"
    static let editing = "Modification…"
    static let cancelEditing = "Annuler la modification"
    static let edit = "Modifier"
    static let delete = "Supprimer"
    static let deleteConfirmation = "Supprimer ce commentaire ?"
    static let cancel = "Annuler"
    static let loadFailed = "Les commentaires n'ont pas pu être chargés."
    static let retry = "Réessayer"
    static let editFailed = "La modification n'a pas pu être enregistrée."
    static let deleteFailed = "Le commentaire n'a pas pu être supprimé."
    /// Author of a comment being sent when the viewer's own name is not known.
    static let you = "Vous"
}
