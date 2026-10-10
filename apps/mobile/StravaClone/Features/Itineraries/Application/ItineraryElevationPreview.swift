import Foundation
import Observation

/// Elevation gain shown while editing (ADR-030 §3). The editor tells it where the track
/// stands; once a gesture is over and every Leg is routed, `metrics-preview` measures the
/// full track. An answer for a track that changed since is dropped.
@Observable
@MainActor
final class ItineraryElevationPreview {
    enum Status: Equatable, Sendable {
        /// No start and finish yet: nothing to measure.
        case idle
        /// The track is changing, or its measure is on its way: the last gain is greyed out.
        case measuring
        /// `metrics` measures the current track.
        case measured
        /// The preview failed: "D+ indisponible", with a retry.
        case unavailable
    }

    /// Where the track stands, as the editor sees it.
    enum Track: Equatable, Sendable {
        /// Fewer than two Waypoints.
        case empty
        /// A gesture is in progress, or a Leg is still being routed.
        case changing
        /// Ready to be measured as is.
        case settled(ItineraryMetricsRequest)
    }

    private(set) var status: Status = .idle
    /// Last metrics received, kept (greyed out) while the next ones are on their way.
    private(set) var metrics: ItineraryMetrics?

    @ObservationIgnored private let previewer: (any ItineraryMetricsPreviewer)?
    /// The request `status` is about: in flight, measured or failed.
    @ObservationIgnored private var target: ItineraryMetricsRequest?
    /// The request whose answer is awaited; any other answer is dropped.
    @ObservationIgnored private var awaited: UUID?
    /// Every request not answered yet, dropped ones included.
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    /// - Parameter previewer: `nil` turns the preview off: the gain stays idle.
    init(previewer: (any ItineraryMetricsPreviewer)?) {
        self.previewer = previewer
    }

    func update(_ track: Track) {
        guard previewer != nil else { return }
        switch track {
        case .empty:
            cancel()
            target = nil
            metrics = nil
            status = .idle
        case .changing:
            cancel()
            target = nil
            status = .measuring
        case .settled(let request):
            guard request != target else { return }
            send(request)
        }
    }

    /// "Réessayer" after a failure: the same track is measured again.
    func retry() {
        guard status == .unavailable, let target else { return }
        send(target)
    }

    /// Waits until every request sent has been answered, applied or dropped.
    func settle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    // MARK: Private

    private func send(_ request: ItineraryMetricsRequest) {
        guard let previewer else { return }
        cancel()
        target = request
        status = .measuring
        let token = UUID()
        let task = Task {
            let outcome: Result<ItineraryMetrics, ItineraryMetricsError>
            do throws(ItineraryMetricsError) {
                outcome = .success(try await previewer.metrics(for: request))
            } catch {
                outcome = .failure(error)
            }
            self.finish(token, with: outcome)
        }
        awaited = token
        tasks[token] = task
    }

    private func finish(_ token: UUID, with outcome: Result<ItineraryMetrics, ItineraryMetricsError>) {
        tasks[token] = nil
        guard awaited == token else { return }
        awaited = nil
        switch outcome {
        case .success(let measured):
            metrics = measured
            status = .measured
        case .failure:
            status = .unavailable
        }
    }

    private func cancel() {
        if let awaited {
            tasks[awaited]?.cancel()
        }
        awaited = nil
    }
}
