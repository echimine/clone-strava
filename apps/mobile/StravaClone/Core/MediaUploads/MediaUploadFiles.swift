import Foundation

/// The local files of the Media being sent (ADR-037 §5): one folder per Media,
/// `<root>/<mediaId>/<file name>`, kept until the confirmation's `201` (a background `PUT`
/// reads its file while it runs). The root is Application Support's `MediaUploads`, excluded
/// from backups; only the Media id is stored, as the app container moves on each update.
struct MediaUploadFiles: Sendable {
    let root: URL

    static func applicationSupport() throws -> MediaUploadFiles {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var root = support.appendingPathComponent("MediaUploads", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        return MediaUploadFiles(root: root)
    }

    func directory(of mediaID: UUID) -> URL {
        root.appendingPathComponent(mediaID.uuidString.lowercased(), isDirectory: true)
    }

    func url(of name: String, mediaID: UUID) -> URL {
        directory(of: mediaID).appendingPathComponent(name, isDirectory: false)
    }

    /// An empty folder for a new export.
    func makeDirectory(of mediaID: UUID) throws -> URL {
        let directory = directory(of: mediaID)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func delete(_ mediaID: UUID) {
        try? FileManager.default.removeItem(at: directory(of: mediaID))
    }

    /// Folders left without a row (an export cut by the app being killed, ADR-037 §6).
    func deleteFolders(except kept: Set<UUID>) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent), !kept.contains(id) else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    func deleteAll() {
        deleteFolders(except: [])
    }
}
