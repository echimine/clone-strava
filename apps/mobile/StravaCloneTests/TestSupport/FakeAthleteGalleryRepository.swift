import Foundation
@testable import StravaClone

/// In-memory `AthleteGalleryRepository` (ADR-025 §3): scripted pages keyed by cursor, recorded calls.
final class FakeAthleteGalleryRepository: AthleteGalleryRepository, @unchecked Sendable {
    private let lock = NSLock()

    /// Answers keyed by cursor (`nil` = first page).
    var pages: [String?: Result<GalleryPage, AthleteError>] = [:]
    private(set) var calls: [(athleteId: String, cursor: String?)] = []

    func gallery(of athleteId: String, cursor: String?) async throws(AthleteError) -> GalleryPage {
        let result = lock.withLock {
            calls.append((athleteId, cursor))
            return pages[cursor] ?? .failure(.network)
        }
        return try result.get()
    }
}

extension GalleryItem {
    static func fixture(
        kind: ActivityMedia.Kind = .photo,
        activity: ActivityID = ActivityID(),
        title: String = "Sortie du lundi"
    ) -> GalleryItem {
        GalleryItem(
            media: .fixture(kind: kind),
            activity: GalleryActivity(id: activity, title: title, startedAt: Date(timeIntervalSince1970: 1_773_644_400))
        )
    }
}
