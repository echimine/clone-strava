import Foundation

/// Elevation gain in the stats card (ADR-030 §3).
extension ItineraryEditorStore {
    /// Last gain measured, "≈" when Open-Meteo provided altitudes; "—" before any.
    var elevationText: String {
        guard let metrics = editor.elevation.metrics else { return "—" }
        return ItineraryMessages.elevationGain(metrics.elevationGain, source: metrics.elevationSource)
    }

    /// While the track changes or its measure is on its way, the gain shown is the last one: greyed out.
    var isElevationStale: Bool {
        editor.elevation.status == .measuring
    }

    /// "D+ indisponible" with a retry button instead of the gain; editing goes on.
    var isElevationUnavailable: Bool {
        editor.elevation.status == .unavailable
    }

    /// Credit of the altitudes behind the gain shown.
    var elevationSourceText: String? {
        guard !isElevationUnavailable, let source = editor.elevation.metrics?.elevationSource else { return nil }
        return ItineraryMessages.elevationSource(source)
    }

    func retryElevation() {
        editor.elevation.retry()
    }
}
