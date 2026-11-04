import UIKit

/// Owns the composition root and picks a Recording up as soon as the app launches (ADR-031 §3):
/// after a relaunch by iOS in the background, the background session and the GPS loop must
/// restart in `didFinishLaunchingWithOptions`, before any screen exists.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let di: Di

    override init() {
        // The UI tests' launch arguments are compiled into debug builds only: a release build
        // never wipes a session or a draft because of its arguments.
        #if DEBUG
        // UI tests launch with `-uiTestResetAuth` to start from a clean, signed-out
        // state regardless of what a previous run left in the Keychain.
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetAuth") {
            AuthSession().clear()
        }
        #endif
        do {
            di = try Di.live()
        } catch {
            fatalError("Unable to open the local database: \(error)")
        }
        super.init()
        #if DEBUG
        // `-uiTestResetOnboarding`: no Onboarding draft to resume (ADR-035 §5).
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetOnboarding") {
            let drafts = GRDBOnboardingDraftRepository(database: di.database)
            Task { try? await drafts.delete() }
        }
        #endif
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        di.start()
        // The sync queue's BGAppRefreshTask must be registered before launch ends (ADR-031 §14).
        di.startBackgroundRefresh()
        // A launch in the background (for location, the sync queue's refresh task…) goes on
        // in the saved phase; a launch in the foreground is the athlete opening it (ADR-031 §10).
        di.resumeRecording(after: RecordingLaunch(
            launchedForLocation: launchOptions?[.location] != nil,
            inBackground: application.applicationState == .background
        ))
        return true
    }

    /// The Media's background session finished its uploads while the app was suspended or
    /// killed (ADR-037 §5): the session, made at launch, receives their events, then iOS's
    /// handler is called.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let handler = UncheckedHandler(run: completionHandler)
        if !di.handleEventsForBackgroundURLSession(identifier, completionHandler: { handler.run() }) {
            completionHandler()
        }
    }
}

/// iOS calls this handler on the main thread once; it crosses to the session's delegate queue.
private struct UncheckedHandler: @unchecked Sendable {
    let run: () -> Void
}
