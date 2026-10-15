import AppIntents
import SwiftUI

@main
struct ProbeApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { ContentView() }
            .onChange(of: scenePhase) { _, phase in
                EventLog.shared.note("scène \(phase)", kind: "scene")
            }
    }
}

/// Apple's documented relaunch setup: recreate the session and liveUpdates immediately.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let keys = launchOptions?.keys.map(\.rawValue).joined(separator: ", ") ?? "aucune"
        EventLog.shared.note("lancement de l'app · options : \(keys)", kind: "launch")
        Probe.shared.resumeAfterLaunch()
        return true
    }
}

// MARK: - Markers from the Action Button or Back Tap (Réglages > Accessibilité > Toucher > Toucher le dos)

struct ToggleMarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Marquer arrêt / reprise"
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let mark = Probe.shared.toggleMark(source: "raccourci")
        return .result(dialog: mark == "stop" ? "Arrêt noté" : "Reprise notée")
    }
}

struct MarkStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Marquer un arrêt"
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Probe.shared.mark("stop", source: "raccourci")
        return .result(dialog: "Arrêt noté")
    }
}

struct MarkGoIntent: AppIntent {
    static var title: LocalizedStringResource = "Marquer une reprise"
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Probe.shared.mark("go", source: "raccourci")
        return .result(dialog: "Reprise notée")
    }
}

struct ProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleMarkIntent(), phrases: ["Marquer dans \(.applicationName)"],
                    shortTitle: "Arrêt / reprise", systemImageName: "flag")
        AppShortcut(intent: MarkStopIntent(), phrases: ["Arrêt dans \(.applicationName)"],
                    shortTitle: "Arrêt", systemImageName: "stop.circle")
        AppShortcut(intent: MarkGoIntent(), phrases: ["Reprise dans \(.applicationName)"],
                    shortTitle: "Reprise", systemImageName: "play.circle")
    }
}
