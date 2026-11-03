import Foundation
@testable import StravaClone

extension ActivityMedia {
    static func fixture(kind: Kind = .photo) -> ActivityMedia {
        let id = UUID()
        let folder = "https://bucket.test/activities/u1/a1/media/\(id.uuidString.lowercased())"
        return ActivityMedia(
            id: id,
            kind: kind,
            width: 2048,
            height: 1536,
            duration: kind == .video ? .seconds(10) : nil,
            url: URL(string: "\(folder)/\(kind == .video ? "original.mp4" : "original.jpg")")!,
            posterURL: kind == .video ? URL(string: "\(folder)/poster.jpg")! : nil,
            thumbURL: URL(string: "\(folder)/thumb.jpg")!
        )
    }
}
