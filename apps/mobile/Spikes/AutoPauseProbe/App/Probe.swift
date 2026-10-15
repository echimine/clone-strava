import CoreLocation
import CoreMotion
import UIKit

enum Sport: String, CaseIterable, Identifiable {
    case run = "course", ride = "vélo", walk = "marche"
    var id: String { rawValue }
}

enum AppState {
    @MainActor static var current: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "?"
        }
    }
}

/// Mimics a Recording's sensors (liveUpdates(.fitness) + CLBackgroundActivitySession, never stopped
/// during a stop) and journals everything: location updates, Core Motion activity, battery, markers.
@MainActor
final class Probe: ObservableObject {
    static let shared = Probe()

    @Published var sport: Sport = Sport(rawValue: UserDefaults.standard.string(forKey: "sport") ?? "") ?? .run {
        didSet { UserDefaults.standard.set(sport.rawValue, forKey: "sport") }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var lastUpdate: Event?
    @Published private(set) var lastMotion: Event?
    @Published private(set) var lastMark: String? = UserDefaults.standard.string(forKey: "lastMark")

    private let log = EventLog.shared
    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var session: CLBackgroundActivitySession?
    private var task: Task<Void, Never>?
    private var batteryObservers: [NSObjectProtocol] = []
    private var lastBatteryLog = Date.distantPast

    /// Persisted so that a relaunch by Core Location knows it must rejoin the session.
    private var persistedRunning: Bool {
        get { UserDefaults.standard.bool(forKey: "running") }
        set { UserDefaults.standard.set(newValue, forKey: "running") }
    }
    private var sessionStart: Date {
        get { UserDefaults.standard.object(forKey: "sessionStart") as? Date ?? Date() }
        set { UserDefaults.standard.set(newValue, forKey: "sessionStart") }
    }

    /// Foreground only: a new CLBackgroundActivitySession cannot be started from the background.
    func start() {
        manager.requestWhenInUseAuthorization()
        persistedRunning = true
        sessionStart = Date()
        lastMark = nil
        UserDefaults.standard.removeObject(forKey: "lastMark")
        var event = Event(kind: "session_start", appState: AppState.current, sport: sport.rawValue)
        event.text = "autorisation \(Self.describe(manager.authorizationStatus)), précision "
            + (manager.accuracyAuthorization == .fullAccuracy ? "complète" : "approximative")
            + ", Core Motion " + Self.describe(CMMotionActivityManager.authorizationStatus())
            + ", iOS \(UIDevice.current.systemVersion)"
        log.append(event)
        begin()
    }

    /// Called from didFinishLaunching: rejoin the session and restart liveUpdates immediately.
    func resumeAfterLaunch() {
        guard persistedRunning, !isRunning else { return }
        log.note("session et liveUpdates recréées au lancement")
        begin()
    }

    func stop() {
        task?.cancel()
        task = nil
        session?.invalidate()
        session = nil
        motion.stopActivityUpdates()
        batteryObservers.forEach(NotificationCenter.default.removeObserver)
        batteryObservers = []
        isRunning = false
        persistedRunning = false
        logBattery(force: true)
        log.append(Event(kind: "session_stop", appState: AppState.current, sport: sport.rawValue))
        logMotionHistory(from: sessionStart, to: Date())
    }

    func mark(_ mark: String, source: String) {
        var event = Event(kind: "marker", appState: AppState.current)
        event.mark = mark
        event.source = source
        log.append(event)
        lastMark = mark
        UserDefaults.standard.set(mark, forKey: "lastMark")
    }

    /// Alternates stop / go, for a single Action Button or Back Tap shortcut.
    func toggleMark(source: String) -> String {
        let next = lastMark == "stop" ? "go" : "stop"
        mark(next, source: source)
        return next
    }

    private func begin() {
        isRunning = true
        session = CLBackgroundActivitySession()
        UIDevice.current.isBatteryMonitoringEnabled = true
        logBattery(force: true)
        let center = NotificationCenter.default
        batteryObservers = [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification]
            .map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { Probe.shared.logBattery(force: true) }
                }
            }
        task = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    handle(update)
                }
            } catch {
                log.note("liveUpdates : \(error.localizedDescription)", kind: "error")
            }
        }
        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { activity in
                guard let activity else { return }
                MainActor.assumeIsolated { Probe.shared.handle(activity, kind: "motion") }
            }
        } else {
            log.note("Core Motion : activité indisponible sur cet appareil", kind: "error")
        }
    }

    private func handle(_ update: CLLocationUpdate) {
        var event = Event(kind: update.location == nil ? "update" : "loc", appState: AppState.current)
        event.stationary = update.isStationary
        if #available(iOS 18.0, *) {
            let flags: [(Bool, String)] = [
                (update.stationary, "stationary"),
                (update.locationUnavailable, "locationUnavailable"),
                (update.accuracyLimited, "accuracyLimited"),
                (update.authorizationDenied, "authorizationDenied"),
                (update.authorizationDeniedGlobally, "authorizationDeniedGlobally"),
                (update.authorizationRestricted, "authorizationRestricted"),
                (update.authorizationRequestInProgress, "authorizationRequestInProgress"),
                (update.insufficientlyInUse, "insufficientlyInUse"),
                (update.serviceSessionRequired, "serviceSessionRequired"),
            ]
            let set = flags.filter(\.0).map(\.1)
            event.flags = set.isEmpty ? nil : set
        }
        if let location = update.location {
            event.ts = location.timestamp.timeIntervalSince1970
            event.lat = location.coordinate.latitude
            event.lon = location.coordinate.longitude
            event.hAcc = location.horizontalAccuracy
            event.spd = location.speed
            event.spdAcc = location.speedAccuracy
        }
        log.append(event)
        lastUpdate = event
        logBattery(force: false)
    }

    private func handle(_ activity: CMMotionActivity, kind: String) {
        var event = Event(kind: kind, appState: AppState.current)
        event.activity = Self.describe(activity)
        event.confidence = activity.confidence.rawValue
        event.start = activity.startDate.timeIntervalSince1970
        log.append(event)
        if kind == "motion" { lastMotion = event }
    }

    /// History survives suspension, unlike the live handler: gives the true transition dates.
    private func logMotionHistory(from start: Date, to end: Date) {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motion.queryActivityStarting(from: start, to: end, to: .main) { activities, error in
            MainActor.assumeIsolated {
                if let error { Probe.shared.log.note("historique Core Motion : \(error.localizedDescription)", kind: "error") }
                activities?.forEach { Probe.shared.handle($0, kind: "motion_hist") }
            }
        }
    }

    private func logBattery(force: Bool) {
        guard force || Date().timeIntervalSince(lastBatteryLog) >= 60 else { return }
        lastBatteryLog = Date()
        let device = UIDevice.current
        var event = Event(kind: "battery", appState: AppState.current)
        event.level = device.batteryLevel
        event.batteryState = switch device.batteryState {
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        default: "unknown"
        }
        event.thermal = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "?"
        }
        log.append(event)
    }

    static func describe(_ activity: CMMotionActivity) -> String {
        let flags: [(Bool, String)] = [
            (activity.stationary, "stationary"), (activity.walking, "walking"), (activity.running, "running"),
            (activity.cycling, "cycling"), (activity.automotive, "automotive"), (activity.unknown, "unknown"),
        ]
        let set = flags.filter(\.0).map(\.1)
        return set.isEmpty ? "none" : set.joined(separator: "+")
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "non demandée"
        case .restricted: "restreinte"
        case .denied: "refusée"
        case .authorizedAlways: "toujours"
        case .authorizedWhenInUse: "app active"
        @unknown default: "?"
        }
    }

    private static func describe(_ status: CMAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "non demandée"
        case .restricted: "restreinte"
        case .denied: "refusée"
        case .authorized: "autorisée"
        @unknown default: "?"
        }
    }
}
