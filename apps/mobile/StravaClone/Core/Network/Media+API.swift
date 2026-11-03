import Foundation

extension Components.Schemas.Media_Output {
    /// The one Media shape of every response (ADR-037 §7), shared as the `Media` OpenAPI component.
    /// Nil for a Media whose id or URLs do not parse, which the API never sends.
    var model: ActivityMedia? {
        guard let uuid = UUID(uuidString: id), let url = URL(string: url), let thumbURL = URL(string: thumbUrl) else {
            return nil
        }
        let mediaKind: ActivityMedia.Kind = switch kind {
        case .photo: .photo
        case .video: .video
        }
        return ActivityMedia(
            id: uuid,
            kind: mediaKind,
            width: width,
            height: height,
            duration: durationMs.map { .milliseconds($0) },
            url: url,
            posterURL: posterUrl.flatMap(URL.init(string:)),
            thumbURL: thumbURL
        )
    }
}

extension Array where Element == Components.Schemas.Media_Output {
    /// An Activity's Media in the API's order.
    var models: [ActivityMedia] { compactMap(\.model) }
}
