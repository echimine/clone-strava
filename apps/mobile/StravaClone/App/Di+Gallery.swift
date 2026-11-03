import Foundation

/// The profile's Galerie tab (ADR-037 §9, §10): mine and another athlete's.
extension Di {
    /// A new one per profile: the Profile tab's lives as long as the app, another athlete's as
    /// long as their pushed page. `message`: the feature's French text for a failed page.
    func makeGalleryStore(message: @escaping @MainActor (AthleteError) -> String) -> AthleteGalleryStore {
        AthleteGalleryStore(
            loadGallery: LoadAthleteGallery(repository: APIAthleteGalleryRepository(apiClient: apiClient)),
            message: message,
            activityChanges: activityChanges,
            analytics: analytics
        )
    }
}
