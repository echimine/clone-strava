import Foundation
import Observation

/// Reports and Blocks from anywhere in the app (ADR-038 §8, §9): the Report sheet, then its
/// confirmation with "Bloquer aussi <prénom>", and the Block confirmation. Online only: a failure
/// shows a toast and hides nothing. What is hidden leaves the lists through `ActivityChanges`
/// (Activities) and the caller's `onHidden` (a comment, a detail or a profile that closes).
@MainActor
@Observable
final class ModerationStore {
    /// The Report sheet of one target.
    struct ReportSheet: Identifiable, Equatable {
        let target: ReportTarget
        var id: String { target.id }
    }

    enum SheetPhase: Equatable {
        case editing
        case sending
        case done(ReportOutcome)
    }

    /// "Bloquer <prénom> ?", waiting for its confirmation.
    struct BlockRequest: Identifiable, Equatable {
        let athlete: ActivityAuthor
        let source: AnalyticsEvent.BlockSource
        var id: String { athlete.id }
    }

    var sheet: ReportSheet?
    var reason: ReportReason?
    var note = "" {
        didSet {
            if note.count > reportNoteMaxLength { note = String(note.prefix(reportNoteMaxLength)) }
        }
    }
    private(set) var sheetPhase = SheetPhase.editing
    /// A failure while the sheet is open, shown over it.
    var sheetToast: String?
    var blockRequest: BlockRequest?
    /// Outcomes and failures once the sheet is closed.
    var toast: String?

    @ObservationIgnored private let reportContent: ReportContent
    @ObservationIgnored private let blockAthlete: BlockAthlete
    @ObservationIgnored private let changes: ActivityChanges
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private var onHidden: (@MainActor (ReportHiding) -> Void)?
    @ObservationIgnored private var onBlocked: (@MainActor () -> Void)?

    init(
        reportContent: ReportContent,
        blockAthlete: BlockAthlete,
        changes: ActivityChanges,
        analytics: any AnalyticsClient = NoAnalyticsClient()
    ) {
        self.reportContent = reportContent
        self.blockAthlete = blockAthlete
        self.changes = changes
        self.analytics = analytics
    }

    var reasons: [ReportReason] {
        sheet.map { ReportReason.choices(for: $0.target.kind) } ?? []
    }

    /// A reason is chosen, and a note given with "Autre".
    var canSend: Bool {
        guard let reason, sheetPhase == .editing else { return false }
        return !reason.requiresNote || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Report

    /// "Signaler": opens the sheet on a blank form.
    func report(_ target: ReportTarget, onHidden: @escaping @MainActor (ReportHiding) -> Void = { _ in }) {
        reason = nil
        note = ""
        sheetPhase = .editing
        sheetToast = nil
        self.onHidden = onHidden
        sheet = ReportSheet(target: target)
    }

    /// "Envoyer". A comment or an Activity is hidden at once, also on "Déjà signalé"; an athlete
    /// or a Segment is never hidden by the Report itself.
    func send() async {
        guard let target = sheet?.target, let reason, canSend else { return }
        sheetPhase = .sending
        do {
            let outcome = try await reportContent(target, reason: reason, note: note)
            sheetPhase = .done(outcome)
            if target.kind == .comment || target.kind == .activity {
                hide(target)
            }
        } catch {
            sheetPhase = .editing
            sheetToast = ModerationMessages.message(for: error)
        }
    }

    func closeSheet() {
        sheet = nil
        if blockRequest?.source == .reportConfirmation {
            blockRequest = nil
        }
    }

    /// "Bloquer aussi <prénom>" in the sheet's confirmation.
    func blockReportedAuthor() {
        guard let author = sheet?.target.author else { return }
        let hidden = onHidden
        requestBlock(author, source: .reportConfirmation) {
            hidden?(.author)
        }
    }

    // MARK: Block

    /// "Bloquer": asks for the confirmation first.
    func requestBlock(
        _ athlete: ActivityAuthor,
        source: AnalyticsEvent.BlockSource = .profile,
        onBlocked: @escaping @MainActor () -> Void = {}
    ) {
        self.onBlocked = onBlocked
        blockRequest = BlockRequest(athlete: athlete, source: source)
    }

    func cancelBlock() {
        blockRequest = nil
        onBlocked = nil
    }

    /// The confirmation's "Bloquer": their Activities leave every list, the sheet closes.
    func confirmBlock() async {
        guard let request = blockRequest else { return }
        blockRequest = nil
        do {
            try await blockAthlete(request.athlete.id)
            analytics.capture(.athleteBlocked(source: request.source))
            changes.publish(.authorHidden(athleteId: request.athlete.id))
            sheet = nil
            toast = ModerationMessages.blocked(request.athlete.firstName)
            onBlocked?()
            onBlocked = nil
        } catch {
            if sheet != nil {
                sheetToast = ModerationMessages.message(for: error)
            } else {
                toast = ModerationMessages.message(for: error)
            }
        }
    }

    private func hide(_ target: ReportTarget) {
        if target.kind == .activity, let uuid = UUID(uuidString: target.targetId) {
            changes.publish(.deleted(ActivityID(uuid)))
        }
        onHidden?(.target)
    }
}
