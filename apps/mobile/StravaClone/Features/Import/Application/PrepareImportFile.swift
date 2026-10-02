import Foundation

/// Turns a file picked in the Files app into an `ImportFile` ready to send, rejecting
/// unsupported or oversized files before any network call (ADR-028 §11).
struct PrepareImportFile: Sendable {
    let staging: ImportFileStaging

    func callAsFunction(_ pickedURL: URL) throws(ImportError) -> ImportFile {
        guard ImportFormat(fileName: pickedURL.lastPathComponent) != nil else {
            throw .unsupportedFile
        }
        let file = try staging.stage(pickedURL)
        guard file.sizeBytes <= importMaxFileBytes else {
            throw .fileTooLarge
        }
        return file
    }
}
