import Foundation
@testable import StravaClone

/// Hand-written `ItineraryMetricsPreviewer` (ADR-025 §3): records every request and
/// answers with `answer`, by default a gain of 10 m per Waypoint measured by IGN.
/// `hold()` suspends answers until `release()`, to observe in-flight states and races.
actor FakeItineraryMetricsPreviewer: ItineraryMetricsPreviewer {
    private(set) var requests: [ItineraryGeometry] = []
    private var answer: @Sendable (ItineraryGeometry) -> Result<ItineraryMetrics, ItineraryMetricsError> = {
        .success(FakeItineraryMetricsPreviewer.metrics(gain: Double($0.waypoints.count * 10)))
    }
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    static func metrics(gain: Double, source: ElevationSource = .ign) -> ItineraryMetrics {
        ItineraryMetrics(distance: Distance(meters: 1_000), elevationGain: gain, elevationSource: source)
    }

    func answer(with answer: @escaping @Sendable (ItineraryGeometry) -> Result<ItineraryMetrics, ItineraryMetricsError>) {
        self.answer = answer
    }

    func answer(_ metrics: ItineraryMetrics) {
        answer = { _ in .success(metrics) }
    }

    func fail(with error: ItineraryMetricsError) {
        answer = { _ in .failure(error) }
    }

    func hold() {
        isHolding = true
    }

    /// Stops holding and lets every suspended request answer.
    func release() {
        isHolding = false
        let continuations = held
        held = []
        continuations.forEach { $0.resume() }
    }

    /// Waits until the previewer has received `count` requests in total.
    func waitForRequests(_ count: Int) async {
        while requests.count < count {
            await Task.yield()
        }
    }

    func metrics(for request: ItineraryGeometry) async throws(ItineraryMetricsError) -> ItineraryMetrics {
        requests.append(request)
        if isHolding {
            await withCheckedContinuation { held.append($0) }
        }
        return try answer(request).get()
    }
}
