import LiveSDK

/// The Live SDK (live.echimine.fr): Nervo is a member app, our API signs each Participant token.
extension Di {
    /// Configures the shared SDK; called each time the Lives open, which refreshes its config.
    func configureLive() async {
        let tokens = APILiveParticipantTokenProvider(apiClient: apiClient)
        await LiveSDK.shared.configure(serverURL: configuration.liveServerURL) {
            try await tokens.token()
        }
    }
}
