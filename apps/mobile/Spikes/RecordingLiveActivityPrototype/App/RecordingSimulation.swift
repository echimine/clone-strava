// PROTOTYPE — throwaway (wayfinder #43, ticket #53). Never merged.
// A fake Recording ticking every second, kept alive in background by live GPS updates (like the real
// Recording), pushing local ActivityKit updates at a chosen rhythm. Every state is forced from the app.

import ActivityKit
import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class RecordingSimulation {
    static let shared = RecordingSimulation()

    enum Cadence: String, CaseIterable, Identifiable {
        case everyPoint = "Chaque point (1 s)"
        case every5s = "Toutes les 5 s"
        case every15s = "Toutes les 15 s"
        case every100m = "Tous les 100 m"
        var id: Self { self }
    }

    enum StaleMargin: String, CaseIterable, Identifiable {
        case none = "Aucune staleDate"
        case thirtySeconds = "30 s"
        case twoMinutes = "2 min"
        var id: Self { self }
        var seconds: TimeInterval? {
            switch self {
            case .none: nil
            case .thirtySeconds: 30
            case .twoMinutes: 120
            }
        }
    }

    enum Dismissal: String, CaseIterable, Identifiable {
        case immediate = "Immédiate"
        case oneMinute = "Après 1 min"
        case systemDefault = "Par défaut (jusqu'à 4 h)"
        var id: Self { self }
    }

    // Settings
    var variant: ProtoVariant = .A { didSet { push(reason: "variante \(variant.rawValue)") } }
    var sport: ProtoSport = .run
    var withItinerary = true
    var itineraryStatus: ItineraryStatus = .onTrack { didSet { push(reason: "état Itinéraire") } }
    var cadence: Cadence = .every5s
    var staleMargin: StaleMargin = .twoMinutes
    /// Stops every update while the app keeps running: what the lock screen shows once the app is killed.
    var updatesFrozen = false { didSet { log(updatesFrozen ? "mises à jour gelées" : "mises à jour reprises"); if !updatesFrozen { push(reason: "dégel") } } }
    var dismissal: Dismissal = .systemDefault

    // Recording
    private(set) var isRecording = false
    private(set) var chronoStart = Date()
    private(set) var pausedAt: Date?
    private(set) var distanceMeters = 0.0
    private(set) var currentSpeedKmh: Double?
    private(set) var hasItinerary = false
    private(set) var frozenRemaining: Double?
    let itineraryName = "Boucle du canal"
    let itineraryTotal = 8_000.0

    // Surfaced state
    private(set) var updateCount = 0
    private(set) var lastPayloadBytes = 0
    private(set) var lastPush: Date?
    private(set) var gpsFixes = 0
    private(set) var lines: [String] = []
    private(set) var orphanCount = 0

    private var activity: Activity<RecordingActivityAttributes>?
    private var lastPushedDistance = 0.0
    private var tickTask: Task<Void, Never>?
    private var gpsTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private let manager = CLLocationManager()

    init() {
        orphanCount = Activity<RecordingActivityAttributes>.activities.count
        log("lancement · \(orphanCount) Live Activity(s) restée(s) d'avant")
    }

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var isPaused: Bool { pausedAt != nil }

    var movingSeconds: Int { Int((pausedAt ?? Date()).timeIntervalSince(chronoStart)) }

    var remainingMeters: Double {
        if let frozenRemaining { return frozenRemaining }
        return max(0, itineraryTotal - distanceMeters)
    }

    // MARK: Actions

    func start() {
        manager.requestWhenInUseAuthorization()
        chronoStart = Date()
        pausedAt = nil
        distanceMeters = 0
        currentSpeedKmh = nil
        hasItinerary = withItinerary
        frozenRemaining = nil
        updateCount = 0
        isRecording = true
        updatesFrozen = false

        do {
            activity = try Activity.request(
                attributes: RecordingActivityAttributes(sport: sport),
                content: content()
            )
            log("Live Activity démarrée (\(sport.label))")
        } catch {
            log("échec de la Live Activity : \(error.localizedDescription) — la Recording continue")
        }
        startGPS()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func togglePause(from source: String) {
        guard isRecording else { return }
        if let pausedAt {
            chronoStart = chronoStart.addingTimeInterval(Date().timeIntervalSince(pausedAt))
            self.pausedAt = nil
            log("reprise (\(source))")
        } else {
            pausedAt = Date()
            currentSpeedKmh = nil
            log("pause (\(source))")
        }
        push(reason: "pause/reprise")
    }

    func skipTenMinutes() {
        guard isRecording, !isPaused else { return }
        chronoStart = chronoStart.addingTimeInterval(-600)
        distanceMeters += sport.metersPerSecond * 600
        push(reason: "+10 min")
    }

    func removeItinerary() {
        hasItinerary = false
        push(reason: "Itinéraire retiré")
    }

    func save() {
        guard let activity else { return finish() }
        let final = content(ending: .init(movingSeconds: movingSeconds))
        let policy: ActivityUIDismissalPolicy = switch dismissal {
        case .immediate: .immediate
        case .oneMinute: .after(Date().addingTimeInterval(60))
        case .systemDefault: .default
        }
        Task { await activity.end(final, dismissalPolicy: policy) }
        log("Enregistrer · fin \(dismissal.rawValue)")
        finish()
    }

    func discard() {
        if let activity { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
        log("Supprimer · fin immédiate")
        finish()
    }

    /// What the real app would do at launch: end whatever a killed Recording left behind.
    func cleanUpOrphans() {
        let all = Activity<RecordingActivityAttributes>.activities.filter { $0.id != activity?.id }
        Task { for a in all { await a.end(nil, dismissalPolicy: .immediate) } }
        log("ménage : \(all.count) Live Activity(s) terminée(s)")
        orphanCount = 0
    }

    /// The state the Live Activity would get right now, for the in-app gallery.
    func previewState(_ v: ProtoVariant) -> LAState {
        var state = content().state
        state.variant = v
        return state
    }

    // MARK: Internals

    private func finish() {
        isRecording = false
        activity = nil
        tickTask?.cancel()
        gpsTask?.cancel()
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    private func tick() {
        guard isRecording else { return }
        if !isPaused {
            let step = sport.metersPerSecond * Double.random(in: 0.85...1.15)
            distanceMeters += step
            currentSpeedKmh = step * 3.6
        }
        if hasItinerary {
            switch itineraryStatus {
            case .offTrack: if frozenRemaining == nil { frozenRemaining = remainingMeters }
            default: frozenRemaining = nil
            }
            if itineraryStatus == .onTrack, remainingMeters <= 0 { itineraryStatus = .finished }
        }
        let since = lastPush.map { Date().timeIntervalSince($0) } ?? .infinity
        let due = switch cadence {
        case .everyPoint: since >= 1
        case .every5s: since >= 5
        case .every15s: since >= 15
        case .every100m: distanceMeters - lastPushedDistance >= 100
        }
        // The staleDate must keep moving even when distance does not (e.g. during a Pause at 100 m cadence).
        let staleRefreshDue = staleMargin.seconds.map { since >= $0 / 2 } ?? false
        if due || staleRefreshDue { push(reason: nil) }
    }

    private func push(reason: String?) {
        guard let activity, isRecording, !updatesFrozen else { return }
        let content = content()
        lastPayloadBytes = (try? JSONEncoder().encode(content.state).count) ?? 0
        lastPush = Date()
        lastPushedDistance = distanceMeters
        updateCount += 1
        if let reason { log("mise à jour forcée : \(reason)") }
        Task { await activity.update(content) }
    }

    private func content(ending: RecordingActivityAttributes.Ending? = nil) -> ActivityContent<RecordingActivityAttributes.ContentState> {
        let hours = Double(movingSeconds) / 3600
        let km = distanceMeters / 1000
        let state = RecordingActivityAttributes.ContentState(
            variant: variant,
            chronoStart: chronoStart,
            pausedAt: ending == nil ? pausedAt : (pausedAt ?? Date()),
            distanceMeters: distanceMeters,
            avgPaceSecondsPerKm: km > 0.01 ? Double(movingSeconds) / km : nil,
            currentSpeedKmh: currentSpeedKmh,
            avgSpeedKmh: hours > 0 ? km / hours : nil,
            itinerary: hasItinerary
                ? .init(name: itineraryName, totalMeters: itineraryTotal, remainingMeters: remainingMeters, status: itineraryStatus)
                : nil,
            ending: ending
        )
        let stale = ending == nil ? staleMargin.seconds.map { Date().addingTimeInterval($0) } : nil
        return ActivityContent(state: state, staleDate: stale)
    }

    private func startGPS() {
        backgroundSession = CLBackgroundActivitySession()
        gpsTask = Task { [weak self] in
            do {
                for try await _ in CLLocationUpdate.liveUpdates(.fitness) {
                    self?.gpsFixes += 1
                }
            } catch {
                self?.log("GPS : \(error.localizedDescription)")
            }
        }
    }

    private func log(_ line: String) {
        lines.insert("\(Date().formatted(.dateTime.hour().minute().second())) · \(line)", at: 0)
        lines = Array(lines.prefix(100))
    }
}
