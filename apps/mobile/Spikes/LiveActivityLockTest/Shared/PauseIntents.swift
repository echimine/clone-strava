import ActivityKit
import AppIntents
import Foundation
import os
#if APP
import UIKit
#endif

/// Button A: default policy (`.alwaysAllowed`).
struct TogglePauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause / reprise (A)"

    func perform() async throws -> some IntentResult {
        await TapRecorder.record(button: "A")
        return .result()
    }
}

/// Button B: same action, but asks iOS to authenticate first.
struct AuthTogglePauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause / reprise (B, auth)"
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult {
        await TapRecorder.record(button: "B")
        return .result()
    }
}

enum TapRecorder {
    static let logger = Logger(subsystem: "fr.echimine.LiveActivityLockTest", category: "tap")

    /// Toggles pause on the running Live Activity and logs where/when the intent ran.
    static func record(button: String) async {
        let context = await RunContext.current()
        let line = "\(timeString(Date())) · \(button) · \(context)"
        logger.notice("intent ran: \(line, privacy: .public)")
        EventLog.append(line)

        guard let activity = Activity<LockTestAttributes>.activities.first else {
            EventLog.append("\(timeString(Date())) · \(button) · aucune Live Activity")
            return
        }
        var state = activity.content.state
        let now = Date()
        if let pausedAt = state.pausedAt {
            state.timerStart = state.timerStart.addingTimeInterval(now.timeIntervalSince(pausedAt))
            state.pausedAt = nil
        } else {
            state.pausedAt = now
        }
        if button == "A" { state.openTaps += 1 } else { state.authTaps += 1 }
        state.lastRun = line
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    static func timeString(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }
}

enum RunContext {
    /// "process · app state · protected data" so the log shows which process ran the intent.
    static func current() async -> String {
        let process = ProcessInfo.processInfo.processName
        #if APP
        let (state, unlocked) = await MainActor.run {
            (UIApplication.shared.applicationState, UIApplication.shared.isProtectedDataAvailable)
        }
        let stateName = switch state {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "?"
        }
        return "\(process) · \(stateName) · \(unlocked ? "données accessibles" : "données protégées")"
        #else
        return "\(process) · extension"
        #endif
    }
}

/// Small persisted log, read back by the app screen.
enum EventLog {
    private static let key = "eventLog"

    static func append(_ line: String) {
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.insert(line, at: 0)
        UserDefaults.standard.set(Array(lines.prefix(200)), forKey: key)
    }

    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
