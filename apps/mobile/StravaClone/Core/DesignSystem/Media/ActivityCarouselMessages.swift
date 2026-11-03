import Foundation

/// French texts of the carousel (ADR-037 §10), for VoiceOver.
enum ActivityCarouselMessages {
    static let soundOn = "Activer le son"
    static let soundOff = "Couper le son"

    /// "Photo", or "Vidéo, 0:10".
    static func label(for media: ActivityMedia) -> String {
        switch media.kind {
        case .photo:
            "Photo"
        case .video:
            media.duration.map { "Vidéo, \(ActivityMediaSlide.durationLabel($0))" } ?? "Vidéo"
        }
    }
}
