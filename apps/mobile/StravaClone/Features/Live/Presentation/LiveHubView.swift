import LiveSDK
import LiveSDKUI
import SwiftUI

/// The Lives, opened by the home header's Live button: the Live SDK's list of Lives in progress
/// (every member app's) with "Lancer un Live", then a Live in full screen. The SDK's screens hand
/// navigation back through their callbacks; this view only adds "Fermer".
struct LiveHubView: View {
    /// Points the SDK at the Live server with our Participant token, before the list loads.
    let configure: @MainActor () async -> Void
    let onClose: () -> Void

    @State private var isConfigured = false
    @State private var screen: LiveHubScreen?

    var body: some View {
        NavigationStack {
            Group {
                if isConfigured {
                    LiveListScreen(onOpenLive: { screen = .live(id: $0) }, onLaunch: { screen = .launch })
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Chargement")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", action: onClose)
                        .accessibilityIdentifier("live.close")
                }
            }
        }
        .liveTheme(Self.theme)
        .task {
            await configure()
            isConfigured = true
        }
        .fullScreenCover(item: $screen) { current in
            Group {
                switch current {
                case .launch:
                    LiveLaunchScreen(onLaunched: { screen = .session($0) }, onClose: { screen = nil })
                case .session(let session):
                    LiveScreen(session: session, onClose: { screen = nil })
                case .live(let id):
                    LiveScreen(liveId: id, onClose: { screen = nil })
                }
            }
            .liveTheme(Self.theme)
        }
    }

    /// Nervo's orange and name on the SDK's screens.
    static let theme = LiveTheme(accent: Theme.accent, label: "Nervo Live")
}

/// What covers the list: "Lancer un Live", the Live just launched, or a Live of the list.
private enum LiveHubScreen: Identifiable {
    case launch
    case session(LiveSession)
    case live(id: String)

    var id: String {
        switch self {
        case .launch: "launch"
        case .session(let session): "session-\(session.id)"
        case .live(let id): "live-\(id)"
        }
    }
}
