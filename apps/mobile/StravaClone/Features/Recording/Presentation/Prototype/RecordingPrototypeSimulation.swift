// PROTOTYPE — throwaway (wayfinder #43, ticket #50 « Écran d'une Recording en cours »).
// Lives only on the `prototype/recording-screen` branch, never merged.
// A fake Recording ticking every second along a loop in Paris, with every state forced
// from the scenario panel, so the three screen variants can be judged without going out.

import Foundation
import Observation

@Observable
@MainActor
final class RecordingPrototypeSimulation {
    enum Phase: String, CaseIterable, Identifiable {
        case running = "En cours"
        case paused = "Pause manuelle"
        case autoPaused = "Pause automatique"
        var id: Self { self }
    }

    enum ItineraryState: String, CaseIterable, Identifiable {
        case onTrack = "Sur le tracé"
        case notYetSnapped = "Pas encore accroché (—)"
        case offTrack = "Hors Itinéraire (hors ligne)"
        case rerouting = "Recalcul en cours"
        case rerouted = "Chemin recalculé"
        case finished = "Itinéraire terminé"
        var id: Self { self }
    }

    enum GPS: String, CaseIterable, Identifiable {
        case ready = "GPS prêt"
        case weak = "Signal faible"
        case lost = "GPS perdu"
        var id: Self { self }
    }

    static let sports: [SportType] = [.run, .ride, .walk, .hike]

    var sport: SportType = .run { didSet { resetPosition() } }
    var phase: Phase = .running { didSet { currentSpeedWindow.removeAll() } }
    var hasItinerary = true
    var itineraryState: ItineraryState = .onTrack
    var gps: GPS = .ready

    private(set) var elapsedSeconds = 23 * 60 + 40
    private(set) var distanceMeters = 0.0
    private(set) var trace: [Coordinate] = []
    private(set) var currentSpeedKmh: Double?
    /// Distance along the loop of the athlete (the Itinerary progression).
    private(set) var progressMeters = 0.0
    private var frozenRemaining: Double?
    private var currentSpeedWindow: [Double] = []

    let loop: [Coordinate]
    let loopLength: Double

    init() {
        loop = Self.makeLoop()
        loopLength = Self.length(of: loop)
        resetPosition()
    }

    // MARK: Derived values

    var position: Coordinate {
        let onLoop = Self.point(on: loop, at: progressMeters)
        guard hasItinerary, [.offTrack, .rerouting, .rerouted].contains(itineraryState) else { return onLoop }
        // 150 m north-east of the track: the athlete took a wrong turn.
        return Coordinate(latitude: onLoop.latitude + 0.0011, longitude: onLoop.longitude + 0.0015)
    }

    /// Recalculated path back to the track (online, ticket #58), from the position to ~400 m further.
    var reroute: [Coordinate] {
        guard hasItinerary, itineraryState == .rerouted else { return [] }
        let rejoin = Self.point(on: loop, at: progressMeters + 400)
        let corner = Coordinate(latitude: position.latitude, longitude: rejoin.longitude)
        return [position, corner, rejoin]
    }

    var rerouteDistance: Double {
        zip(reroute, reroute.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1).meters }
    }

    /// `nil` = « — ».
    var remainingMeters: Double? {
        guard hasItinerary else { return nil }
        switch itineraryState {
        case .onTrack: return max(0, loopLength - progressMeters)
        case .notYetSnapped: return nil
        case .offTrack, .rerouting: return frozenRemaining ?? max(0, loopLength - progressMeters)
        case .rerouted: return rerouteDistance + max(0, loopLength - progressMeters - 400)
        case .finished: return 0
        }
    }

    var itineraryProgress: Double {
        guard let remainingMeters else { return 0 }
        return min(1, max(0, 1 - remainingMeters / loopLength))
    }

    var isPaused: Bool { phase != .running }
    var isOnFoot: Bool { sport != .ride }

    // MARK: Formatted stats (#47 formats)

    var chronoText: String {
        let h = elapsedSeconds / 3600, m = (elapsedSeconds % 3600) / 60, s = elapsedSeconds % 60
        return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
    }

    var distanceText: String {
        (distanceMeters / 1000).formatted(.number.precision(.fractionLength(2)).locale(ActivityFormatters.locale))
    }

    var averagePaceText: String {
        guard elapsedSeconds >= 30, distanceMeters > 0 else { return "–" }
        let secondsPerKm = Double(elapsedSeconds) / (distanceMeters / 1000)
        guard secondsPerKm < 3600 else { return "–" }
        let total = Int(secondsPerKm.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    var averageSpeedText: String {
        guard elapsedSeconds > 0 else { return "0,0" }
        return Self.kmh(distanceMeters / Double(elapsedSeconds) * 3.6)
    }

    var currentSpeedText: String {
        guard !isPaused, let currentSpeedKmh else { return "–" }
        return Self.kmh(currentSpeedKmh)
    }

    var remainingText: String {
        guard let remainingMeters else { return "—" }
        return (remainingMeters / 1000).formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))
    }

    /// Small line under the remaining distance, `nil` when on track.
    var itineraryCaption: String? {
        guard hasItinerary else { return nil }
        switch itineraryState {
        case .onTrack: return nil
        case .notYetSnapped: return "Rejoignez le tracé"
        case .offTrack: return "Hors Itinéraire"
        case .rerouting: return "Hors Itinéraire · recalcul…"
        case .rerouted: return "Chemin recalculé"
        case .finished: return "Itinéraire terminé"
        }
    }

    /// Full state, shown in the scenario panel (prototype rule: surface the state).
    var stateDump: String {
        """
        sport=\(sport.code) phase=\(phase.rawValue) gps=\(gps.rawValue)
        chrono=\(chronoText) distance=\(distanceText) km
        allure moy=\(averagePaceText) vit. act.=\(currentSpeedText) vit. moy=\(averageSpeedText)
        itinéraire=\(hasItinerary ? itineraryState.rawValue : "aucun")
        restant=\(remainingText) km progression=\(Int(progressMeters)) / \(Int(loopLength)) m
        """
    }

    // MARK: Actions

    func pause() { phase = .paused }
    func resume() { phase = .running }
    func removeItinerary() { hasItinerary = false }

    func setItineraryState(_ state: ItineraryState) {
        if [.offTrack, .rerouting].contains(state) {
            frozenRemaining = max(0, loopLength - progressMeters)
        }
        itineraryState = state
    }

    /// One second of Recording: the chrono ticks without waiting for GPS, the position
    /// advances only outside a Pause.
    func tick() {
        guard !isPaused else { return }
        elapsedSeconds += 1
        guard gps != .lost, itineraryState != .finished || !hasItinerary else { return }
        let speed = speedMs
        progressMeters = min(loopLength, progressMeters + speed)
        distanceMeters += speed
        trace.append(position)
        currentSpeedWindow.append(speed * 3.6 + Double.random(in: -1.2...1.2))
        if currentSpeedWindow.count > 5 { currentSpeedWindow.removeFirst() }
        currentSpeedKmh = currentSpeedWindow.reduce(0, +) / Double(currentSpeedWindow.count)
    }

    // MARK: Private

    private var speedMs: Double {
        switch sport {
        case .ride: 7.4
        case .walk: 1.4
        case .hike: 1.2
        default: 3.2
        }
    }

    /// Start of the scene: a third of the loop already done, at the sport's pace.
    private func resetPosition() {
        progressMeters = loopLength / 3
        distanceMeters = progressMeters
        elapsedSeconds = Int(progressMeters / speedMs)
        trace = stride(from: 0, through: progressMeters, by: 20).map { Self.point(on: loop, at: $0) }
        currentSpeedWindow.removeAll()
        currentSpeedKmh = speedMs * 3.6
    }

    private static func kmh(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))
    }

    /// ~4.5 km loop around the Buttes-Chaumont, wobbly so it reads as a real track.
    private static func makeLoop() -> [Coordinate] {
        let center = (lat: 48.8800, lon: 2.3830)
        return (0...240).map { i in
            let t = Double(i) / 240 * 2 * .pi
            let wobble = 1 + 0.12 * sin(5 * t) + 0.05 * cos(11 * t)
            return Coordinate(
                latitude: center.lat + 0.0055 * wobble * sin(t),
                longitude: center.lon + 0.0095 * wobble * cos(t)
            )
        }
    }

    private static func length(of line: [Coordinate]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1).meters }
    }

    private static func point(on line: [Coordinate], at meters: Double) -> Coordinate {
        var remaining = meters
        for (a, b) in zip(line, line.dropFirst()) {
            let segment = a.distance(to: b).meters
            if remaining <= segment, segment > 0 {
                let f = remaining / segment
                return Coordinate(
                    latitude: a.latitude + (b.latitude - a.latitude) * f,
                    longitude: a.longitude + (b.longitude - a.longitude) * f
                )
            }
            remaining -= segment
        }
        return line.last ?? Coordinate(latitude: 0, longitude: 0)
    }
}
