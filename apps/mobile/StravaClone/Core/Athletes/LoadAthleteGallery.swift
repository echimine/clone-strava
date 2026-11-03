import Foundation

/// One page of an athlete's Gallery (ADR-037 §9).
struct LoadAthleteGallery: Sendable {
    let repository: any AthleteGalleryRepository

    func callAsFunction(athleteId: String, cursor: String? = nil) async throws(AthleteError) -> GalleryPage {
        try await repository.gallery(of: athleteId, cursor: cursor)
    }
}
