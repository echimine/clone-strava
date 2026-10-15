import ActivityKit
import CoreLocation
import SwiftUI

@main
struct LockTestApp: App {
    init() {
        // A cold launch caused by a button tap shows up right before the intent's own line.
        EventLog.append("\(TapRecorder.timeString(Date())) · lancement de l'app")
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Mimics a Recording: live location updates kept alive in background.
@MainActor
final class GPSKeeper: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var fixes = 0
    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    private var task: Task<Void, Never>?

    func start() {
        manager.requestWhenInUseAuthorization()
        session = CLBackgroundActivitySession()
        isRunning = true
        task = Task {
            do {
                for try await _ in CLLocationUpdate.liveUpdates(.fitness) {
                    fixes += 1
                }
            } catch {
                EventLog.append("GPS: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        task?.cancel()
        session?.invalidate()
        session = nil
        isRunning = false
    }
}

struct ContentView: View {
    @StateObject private var gps = GPSKeeper()
    @Environment(\.scenePhase) private var scenePhase
    @State private var log = EventLog.lines
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Live Activity") {
                    Text(ActivityAuthorizationInfo().areActivitiesEnabled
                         ? "Live Activities autorisées" : "Live Activities désactivées dans Réglages")
                    Button("Démarrer la Live Activity", action: startActivity)
                    Button("Terminer toutes les Live Activities", role: .destructive, action: endActivities)
                    if !message.isEmpty { Text(message).font(.caption) }
                }
                Section("GPS (comme une Recording)") {
                    Toggle("GPS en arrière-plan", isOn: Binding(
                        get: { gps.isRunning },
                        set: { $0 ? gps.start() : gps.stop() }
                    ))
                    Text("Positions reçues : \(gps.fixes)").font(.caption)
                }
                Section {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                } header: {
                    HStack {
                        Text("Journal")
                        Spacer()
                        Button("Effacer") { EventLog.clear(); log = [] }
                    }
                }
            }
            .navigationTitle("LA Lock Test")
            .refreshable { log = EventLog.lines }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { log = EventLog.lines }
        }
    }

    private func startActivity() {
        let state = LockTestAttributes.ContentState(timerStart: Date())
        do {
            _ = try Activity.request(
                attributes: LockTestAttributes(),
                content: ActivityContent(state: state, staleDate: nil)
            )
            message = "Live Activity démarrée"
        } catch {
            message = "Échec : \(error.localizedDescription)"
        }
    }

    private func endActivities() {
        Task {
            for activity in Activity<LockTestAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            message = "Live Activities terminées"
        }
    }
}
