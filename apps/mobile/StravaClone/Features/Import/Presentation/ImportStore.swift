import Foundation
import Observation

/// State of the activity import, from the file picker to the final status (ADR-028).
@Observable
@MainActor
final class ImportStore {
    /// File waiting for confirmation (sheet item).
    struct Confirmation: Identifiable, Equatable {
        let id = UUID()
        let file: ImportFile
        /// `true` when reopened after an `unknown_sport` failure.
        let sportRequired: Bool
    }

    enum Banner: Equatable {
        case uploading(fileName: String)
        case processing(fileName: String)
        case imported(fileName: String)
        case duplicate(fileName: String)
        case stillProcessing(fileName: String)
        case failed(message: String, canPickSport: Bool)
    }

    var isPickingFile = false
    var confirmation: Confirmation?
    private(set) var banner: Banner?

    @ObservationIgnored private let prepareFile: PrepareImportFile
    @ObservationIgnored private let importFile: ImportActivityFile
    @ObservationIgnored private let tracker: ImportTracker
    @ObservationIgnored private var lastFile: ImportFile?

    init(prepareFile: PrepareImportFile, importFile: ImportActivityFile, tracker: ImportTracker) {
        self.prepareFile = prepareFile
        self.importFile = importFile
        self.tracker = tracker
    }

    /// "+" → "Importer une activité".
    func startImport() {
        isPickingFile = true
    }

    func filePicked(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        do {
            confirmation = Confirmation(file: try prepareFile(url), sportRequired: false)
        } catch {
            banner = .failed(message: ImportMessages.message(for: error), canPickSport: false)
        }
    }

    func confirm(_ options: ImportOptions) async {
        guard let confirmation else { return }
        self.confirmation = nil
        let file = confirmation.file
        lastFile = file
        banner = .uploading(fileName: file.fileName)

        // One id per attempt: replays of the same attempt reuse it (ADR-028 §3).
        let id = UUID()
        do {
            let sent = try await importFile(id: id, file: file, options: options)
            if sent.status.isFinal {
                show(sent)
                return
            }
            banner = .processing(fileName: file.fileName)
            if let finished = await tracker.waitForFinalStatus(id: id) {
                show(finished)
            } else {
                banner = .stillProcessing(fileName: file.fileName)
            }
        } catch {
            banner = .failed(message: ImportMessages.message(for: error), canPickSport: false)
        }
    }

    func cancelConfirmation() {
        confirmation = nil
    }

    /// After `unknown_sport`: same file, the sport must be chosen this time.
    func pickSportAgain() {
        guard let lastFile else { return }
        banner = nil
        confirmation = Confirmation(file: lastFile, sportRequired: true)
    }

    func dismissBanner() {
        banner = nil
    }

    private func show(_ result: ActivityImport) {
        switch result.status {
        case .imported:
            banner = .imported(fileName: result.fileName)
        case .duplicate:
            banner = .duplicate(fileName: result.fileName)
        case .failed:
            banner = .failed(
                message: ImportMessages.message(forCode: result.errorCode),
                canPickSport: result.errorCode == "unknown_sport"
            )
        case .pending, .processing:
            banner = .stillProcessing(fileName: result.fileName)
        }
    }
}
