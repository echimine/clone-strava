import Foundation

/// Distance and elevation gain of an Itinerary as the API computes them on save
/// (ADR-030 §3): the preview shows exactly the figures that will be saved.
struct ItineraryMetrics: Equatable, Sendable {
    let distance: Distance
    /// Meters, with a 2 m hysteresis over the whole track.
    let elevationGain: Double
    let elevationSource: ElevationSource
}

extension ElevationSource {
    /// Open-Meteo is a surface model (buildings, trees): any of its altitudes makes the
    /// gain approximate, shown with "≈".
    var isApproximate: Bool {
        self != .ign
    }
}

/// Why the metrics could not be previewed. Either way the editor shows the gain as
/// unavailable with a retry button, and nothing is blocked.
enum ItineraryMetricsError: Error, Equatable, Sendable {
    case offline
    case unavailable
}

/// `POST /v1/itineraries/metrics-preview` port (ADR-007): runs the save computation and
/// writes nothing. Faked in tests.
protocol ItineraryMetricsPreviewer: Sendable {
    func metrics(for geometry: ItineraryGeometry) async throws(ItineraryMetricsError) -> ItineraryMetrics
}
