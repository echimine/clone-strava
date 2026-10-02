import Foundation

/// Copies a picked file into the app's temporary directory: the Files app only grants
/// security-scoped access for the duration of the pick, while the upload runs later.
struct TemporaryImportFileStager: ImportFileStaging {
    func stage(_ pickedURL: URL) throws(ImportError) -> ImportFile {
        guard let format = ImportFormat(fileName: pickedURL.lastPathComponent) else {
            throw .unsupportedFile
        }
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { pickedURL.stopAccessingSecurityScopedResource() }
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: "imports", directoryHint: .isDirectory)
        let destination = directory.appending(path: "\(UUID().uuidString).\(format.rawValue)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: pickedURL, to: destination)
            let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int ?? 0
            return ImportFile(localURL: destination, fileName: pickedURL.lastPathComponent, format: format, sizeBytes: size)
        } catch {
            throw .unreadableFile
        }
    }
}
