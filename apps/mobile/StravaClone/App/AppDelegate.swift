import UIKit

/// Owns the composition root and picks a Recording up as soon as the app launches (ADR-031 §3):
/// after a relaunch by iOS in the background, the background session and the GPS loop must
/// restart in `didFinishLaunchingWithOptions`, before any screen exists.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let di: Di

    override init() {
        // The UI tests' launch arguments are compiled into debug builds only: a release build
        // never wipes a session, a consent or a draft because of its arguments.
        #if DEBUG
        // UI tests launch with `-uiTestResetAuth` to start from a clean, signed-out
        // state regardless of what a previous run left in the Keychain.
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetAuth") {
            AuthSession().clear()
        }
        // `-uiTestResetMeasurementConsent`: a first launch again, so the consent sheet opens.
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetMeasurementConsent") {
            UserDefaultsMeasurementConsentPreferences().forget()
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
}
