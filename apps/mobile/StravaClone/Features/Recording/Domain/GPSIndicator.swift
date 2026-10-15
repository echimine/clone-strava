import Foundation

/// GPS indicator of the pre-start and Recording screens (ADR-031 §2). Never blocks Start.
enum GPSIndicator: Equatable, Sendable {
    /// "Recherche du GPS…"
    case searching
    /// "GPS prêt": accuracy ≤ 50 m.
    case ready
    /// "Position approximative".
    case approximate

    init(position: LocationSample?, isAccuracyReduced: Bool) {
        guard let position else {
            self = .searching
            return
        }
        let accurate = position.horizontalAccuracy >= 0 && position.horizontalAccuracy <= ProvisionalDistance.maxAccuracyM
        self = accurate && !isAccuracyReduced ? .ready : .approximate
    }
}
