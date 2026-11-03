import Foundation

/// My photo (ADR-037 §2): the Profile tab's, and the one of "Ajoute une photo de profil".
extension Di {
    /// A new editor: one per screen that offers the photo menu (`.avatarPicker`). Network
    /// required: offline, nothing is sent.
    func makeAvatarEditor() -> AvatarEditor {
        let connectivityMonitor = connectivityMonitor
        return AvatarEditor(
            repository: APIAvatarRepository(apiClient: apiClient),
            analytics: analytics,
            imageLoader: imageLoader,
            isOnline: { connectivityMonitor.status.isConnected }
        )
    }
}
