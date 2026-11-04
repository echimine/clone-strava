import Foundation

/// The Activity a Gallery Media belongs to: the viewer's date and "titre · Voir l'activité ›"
/// pill (ADR-037 §9, §10).
struct GalleryActivity: Hashable, Sendable {
    let id: ActivityID
    let title: String
    let startedAt: Date
}

/// One Media of an athlete's Gallery (ADR-037 §9), with its Activity.
struct GalleryItem: Identifiable, Hashable, Sendable {
    let media: ActivityMedia
    var activity: GalleryActivity

    var id: UUID { media.id }
}

/// One page of a Gallery, newest Activity first then the Media order; `nextCursor` is nil on
/// the last page.
struct GalleryPage: Equatable, Sendable {
    let items: [GalleryItem]
    let nextCursor: String?
}

/// Reads an athlete's Gallery, limited to what the viewer may see (ADR-037 §9). Implemented over
/// the API in `Core/Athletes`, faked in tests.
protocol AthleteGalleryRepository: Sendable {
    func gallery(of athleteId: String, cursor: String?) async throws(AthleteError) -> GalleryPage
}
