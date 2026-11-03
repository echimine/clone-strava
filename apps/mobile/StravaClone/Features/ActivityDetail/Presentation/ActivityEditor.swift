import Foundation
import Observation

/// The edit sheet of an Activity and what saving it does (ADR-033 §7), for one screen: the
/// detail ("⋯" > "Modifier") or the feed (context menu of a card). Online and optimistic: the
/// sheet closes and the new values show at once; a failure brings the previous ones back with
/// a toast, and a `422` reopens the sheet with the athlete's input. An Activity gone meanwhile
/// (`404`) becomes unavailable instead.
@Observable
@MainActor
final class ActivityEditor {
    /// The sheet's fields. Present while the sheet is shown.
    struct Form: Identifiable, Equatable {
        let id: ActivityID
        var title: String
        var description: String
        var sport: SportType
        var visibility: ActivityVisibility
        /// "Photos et vidéos" (ADR-037 §10).
        var media: MediaDraft
        /// The map tile of the strip.
        let route: EncodedPolyline?
        /// Why the server turned the last save down (`422`).
        var errorMessage: String?

        /// - Parameter media: the Activity's Media in carousel order, those still being sent
        ///   included; the detail's own by default.
        init(detail: ActivityDetail, media: [ActivityMedia]? = nil) {
            id = detail.id
            title = detail.title
            description = detail.description ?? ""
            sport = detail.sport
            visibility = detail.visibility
            route = detail.route
            self.media = MediaDraft(media: media ?? detail.media, hasMap: detail.route != nil, mediaFirst: detail.mediaFirst)
        }

        /// "Enregistrer" is disabled while the title is blank.
        var canSave: Bool { !Self.trimmed(title).isEmpty }

        var edit: ActivityEdit {
            let description = Self.trimmed(description)
            return ActivityEdit(
                title: Self.trimmed(title),
                description: description.isEmpty ? nil : description,
                sport: sport,
                visibility: visibility,
                mediaOrder: media.hasChanges ? media.order : nil
            )
        }

        /// The sports the picker offers: every active one (ADR-033 §4); an unknown current sport
        /// stays selectable.
        var sports: [SportType] {
            SportType.active.contains(sport) ? SportType.active : SportType.active + [sport]
        }

        private static func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The sheet, shown while not nil.
    var form: Form?
    /// A save or an opening that failed.
    var toast: String?

    /// The screen's own copy of the Activity, e.g. the detail: called with the optimistic
    /// values, then the server's, or the previous ones on failure.
    @ObservationIgnored var onChange: @MainActor (ActivityDetail) -> Void = { _ in }
    /// The screen's own copy is gone: the Activity was deleted or is no longer visible (`404`).
    @ObservationIgnored var onUnavailable: @MainActor () -> Void = {}
    @ObservationIgnored private let loadDetail: LoadActivityDetail
    @ObservationIgnored private let updateActivity: UpdateActivity
    @ObservationIgnored private let changes: ActivityChanges
    /// The Media queue; nil where Media cannot be added (previews).
    @ObservationIgnored private let mediaUploads: ActivityMediaUploads?
    /// The Activity the sheet edits, as it was when the sheet opened.
    @ObservationIgnored private var original: ActivityDetail?

    /// - Parameter changes: where every value shown is published, for the feed's card.
    init(
        loadDetail: LoadActivityDetail,
        updateActivity: UpdateActivity,
        changes: ActivityChanges,
        mediaUploads: ActivityMediaUploads? = nil
    ) {
        self.loadDetail = loadDetail
        self.updateActivity = updateActivity
        self.changes = changes
        self.mediaUploads = mediaUploads
    }

    /// "Modifier" on the detail: the sheet opens on what it shows.
    func edit(_ detail: ActivityDetail) {
        original = detail
        form = Form(detail: detail, media: mediaUploads?.board.media(of: detail.id, merging: detail.media))
    }

    /// "Modifier" on a feed card: the card lacks the description and the visibility, so the
    /// detail is read first.
    func edit(id: ActivityID) async {
        do {
            edit(try await loadDetail(id))
        } catch {
            toast = ActivityDetailMessages.message(for: error)
        }
    }

    func cancel() {
        form = nil
    }

    /// "Enregistrer". The Media just picked are queued at once (ADR-037 §5): the sheet is already
    /// closed, they show in the author's carousel and go in the background.
    func save(_ submitted: Form) async {
        guard submitted.canSave, let previous = original, previous.id == submitted.id else { return }
        form = nil
        let edit = submitted.edit
        if submitted.media.hasChanges, let mediaUploads {
            await mediaUploads.enqueue(submitted.media.queued, previous.id)
        }
        show(edit.applied(to: previous))
        do {
            show(try await updateActivity(previous.id, with: edit))
        } catch .notFound {
            // Deleted or no longer visible meanwhile (ADR-033 §3): nothing to roll back to.
            onUnavailable()
            changes.publish(.deleted(previous.id))
        } catch {
            show(previous)
            if case .invalid(let code) = error {
                var reopened = submitted
                reopened.errorMessage = ActivityDetailMessages.editRefused(code: code)
                form = reopened
            } else {
                toast = ActivityDetailMessages.editFailed(error)
            }
        }
    }

    private func show(_ detail: ActivityDetail) {
        onChange(detail)
        changes.publish(.updated(detail.post))
    }
}
