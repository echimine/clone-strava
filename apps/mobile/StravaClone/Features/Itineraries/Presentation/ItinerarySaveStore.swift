import Foundation
import Observation

/// "Enregistrer" in the editor (ADR-030 §6): the name, the save, and its retry. The id is
/// generated once, when the editor opens, so every retry replays the same `POST` and never
/// creates a duplicate. After "Modifier", the save replaces the same Itinerary (`PUT`).
/// A failure leaves the editor's draft untouched.
@Observable
@MainActor
final class ItinerarySaveStore {
    enum Phase: Equatable {
        case editing
        case saving
        case failed(message: String, canRetry: Bool)
        case saved
    }

    let id: ItineraryID
    var name = ""
    private(set) var phase = Phase.editing

    /// What "Enregistrer" does: create a new Itinerary, or replace an edited one.
    private enum Target {
        case create(SaveItinerary)
        case update(UpdateItinerary)
    }

    @ObservationIgnored private let target: Target

    init(save: SaveItinerary, id: ItineraryID = ItineraryID()) {
        target = .create(save)
        self.id = id
    }

    /// "Modifier": saves on the edited Itinerary's id, under its current name until renamed.
    init(update: UpdateItinerary, itinerary: SavedItinerary) {
        target = .update(update)
        id = itinerary.id
        name = itinerary.name
    }

    var isNameValid: Bool {
        ItineraryDraft.nameLength.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }

    /// Why "Enregistrer" is unavailable for this draft, or `nil` when it can be saved.
    func blocker(for draft: ItineraryDraft) -> String? {
        draft.saveIssue.map(ItineraryMessages.saveIssue)
    }

    /// Back to naming after a failure, e.g. when the sheet is dismissed.
    func dismissFailure() {
        if case .failed = phase {
            phase = .editing
        }
    }

    func save(_ draft: ItineraryDraft) async {
        guard phase != .saving else { return }
        let creation: ItineraryCreation
        do {
            creation = try draft.creation(id: id, name: name)
        } catch {
            phase = .failed(message: ItineraryMessages.saveIssue(error), canRetry: false)
            return
        }
        phase = .saving
        do {
            switch target {
            case .create(let saveItinerary): _ = try await saveItinerary(creation)
            case .update(let updateItinerary): _ = try await updateItinerary(creation)
            }
            phase = .saved
        } catch {
            phase = .failed(message: ItineraryMessages.saveFailed(error), canRetry: error.isRetryable)
        }
    }
}
