import Foundation

/// The athlete's `defaultVisibility` (`GET /v1/me`, ADR-031 §13), cached in `UserDefaults` for
/// the finish screen, which may open offline: `public` while it was never loaded. Refreshed by
/// the app shell on sign-in and each return to the foreground, forgotten on sign-out.
struct DefaultVisibilityCache: DefaultVisibilityProviding, @unchecked Sendable {
    private static let key = "activities.defaultVisibility"

    let apiClient: APIClient
    let defaults: UserDefaults

    init(apiClient: APIClient, defaults: UserDefaults = .standard) {
        self.apiClient = apiClient
        self.defaults = defaults
    }

    var cachedDefaultVisibility: ActivityVisibility {
        defaults.string(forKey: Self.key).flatMap(ActivityVisibility.init(rawValue:)) ?? .public
    }

    /// Loads `GET /v1/me`; the cached value stays as it is on failure.
    func refresh() async {
        guard let me: Components.Schemas.MeResponseDto_Output = try? await apiClient.get("/v1/me"),
              let visibility = ActivityVisibility(rawValue: me.defaultVisibility.rawValue)
        else { return }
        defaults.set(visibility.rawValue, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
