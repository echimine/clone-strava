import UIKit

/// Owns the composition root and picks a Recording up as soon as the app launches (ADR-031 §3):
/// after a relaunch by iOS in the background, the background session and the GPS loop must
/// restart in `didFinishLaunchingWithOptions`, before any screen exists.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let di: Di

    override init() {
        // UI tests launch with `-uiTestResetAuth` to start from a clean, signed-out
        // state regardless of what a previous run left in the Keychain.
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetAuth") {
            AuthSession().clear()
        }
        do {
            di = try Di.live()
        } catch {
            fatalError("Unable to open the local database: \(error)")
        }
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        di.start()
        // iOS relaunches the app for location with this key; any other launch after the app
        // was killed is the athlete opening it (ADR-031 §10).
        di.resumeRecording(after: launchOptions?[.location] != nil ? .relaunchedInBackground : .openedByAthlete)
        return true
    }
}
