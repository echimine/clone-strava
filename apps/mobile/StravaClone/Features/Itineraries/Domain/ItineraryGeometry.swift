import Foundation

/// An Itinerary's `{ waypoints, legs }` as the API takes, measures and stores them
/// (ADR-030 §5, §6): what `metrics-preview` measures, what a save sends, what "Modifier"
/// reopens.
struct ItineraryGeometry: Equatable, Sendable {
    /// A Leg as the API knows it: a `follow` Leg carries the router's geometry as is, a
    /// `straight` one nothing.
    enum Leg: Equatable, Sendable {
        case follow(EncodedPolyline)
        case straight
    }

    let waypoints: [Coordinate]
    /// Leg *n* joins Waypoints *n* and *n + 1*.
    let legs: [Leg]
}
