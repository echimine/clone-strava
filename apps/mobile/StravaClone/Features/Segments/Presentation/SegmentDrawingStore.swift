import Foundation
import Observation

/// The card under the editor while a Segment is drawn (ADR-039 §15): distance, D+ and average
/// grade live (the server measures each settled path through `preview`), and « Continuer »,
/// greyed out with a message while a rule fails. Offline, « Continuer » stays active and says
/// « Connexion requise ».
@Observable
@MainActor
final class SegmentDrawingStore {
    let sport: SegmentSport
    private(set) var drawing = SegmentDrawing.empty
    /// The server's measure of the current settled path, if it came back.
    private(set) var measured: SegmentPreview?
    private(set) var isMeasuring = false
    private(set) var isContinuing = false
    private(set) var message: String?
    /// Set by « Continuer »: the preview screen opens on it.
    var next: SegmentCandidate?

    @ObservationIgnored private let preview: PreviewSegment
    @ObservationIgnored private let isOnline: @MainActor () -> Bool
    @ObservationIgnored private let debounce: Duration
    /// The path `measured` and the task in flight are about.
    @ObservationIgnored private var target: [Coordinate]?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        sport: SegmentSport,
        preview: PreviewSegment,
        isOnline: @escaping @MainActor () -> Bool,
        debounce: Duration = .milliseconds(400)
    ) {
        self.sport = sport
        self.preview = preview
        self.isOnline = isOnline
        self.debounce = debounce
    }

    // MARK: State

    private var settledPath: [Coordinate]? {
        if case .settled(let path) = drawing.path { path } else { nil }
    }

    private var violations: [SegmentRuleViolation] {
        settledPath.map(sport.violations(of:)) ?? []
    }

    /// Why « Continuer » is greyed out; nil once the path can become a Segment.
    var blocker: String? {
        switch drawing.path {
        case .empty: SegmentMessages.placeStartAndFinish
        case .changing: nil
        case .settled: violations.first.map { SegmentMessages.violation($0, sport: sport) }
        }
    }

    var canContinue: Bool {
        settledPath != nil && violations.isEmpty && !isContinuing
    }

    var distanceText: String {
        ActivityFormatters.distance(measured?.figures.distance ?? drawing.distance)
    }

    var elevationGainText: String {
        measured.map { ActivityFormatters.elevation($0.figures.elevationGain) } ?? "–"
    }

    var averageGradeText: String {
        measured.map { SegmentMessages.grade($0.figures.averageGrade) } ?? "–"
    }

    // MARK: Actions

    /// The editor's path changed: a settled one is measured, after a short pause.
    func update(_ drawing: SegmentDrawing) {
        guard drawing != self.drawing else { return }
        self.drawing = drawing
        message = nil
        guard let path = settledPath else {
            cancel()
            measured = nil
            return
        }
        guard path != target else { return }
        measured = nil
        guard violations.isEmpty || violations == [.loop] else {
            cancel()
            return
        }
        measure(path, after: debounce)
    }

    /// « Continuer »: the preview of the measured path, measured again if the live one failed.
    func continueTapped() async {
        guard let path = settledPath, canContinue else { return }
        guard isOnline() else {
            message = SegmentMessages.connectionRequired
            return
        }
        isContinuing = true
        defer { isContinuing = false }
        if measured == nil || target != path {
            measure(path, after: .zero)
            await settle()
        }
        guard let measured, target == path else {
            message = message ?? SegmentMessages.unavailable
            return
        }
        if let violation = measured.violations.first {
            message = SegmentMessages.violation(violation, sport: sport)
            return
        }
        next = SegmentCandidate(sport: sport, points: path, preview: measured)
    }

    func dismissMessage() {
        message = nil
    }

    /// Waits for the measure in flight.
    func settle() async {
        await task?.value
    }

    // MARK: Private

    private func measure(_ path: [Coordinate], after delay: Duration) {
        cancel()
        target = path
        isMeasuring = true
        task = Task { [preview, sport] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let outcome: Result<SegmentPreview, SegmentError>
            do throws(SegmentError) {
                outcome = .success(try await preview(sport: sport, points: path))
            } catch {
                outcome = .failure(error)
            }
            guard !Task.isCancelled, self.target == path else { return }
            self.isMeasuring = false
            switch outcome {
            case .success(let preview):
                self.measured = preview
                self.message = nil
            case .failure(.offline): self.message = SegmentMessages.connectionRequired
            case .failure: self.message = SegmentMessages.unavailable
            }
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        target = nil
        isMeasuring = false
    }
}
