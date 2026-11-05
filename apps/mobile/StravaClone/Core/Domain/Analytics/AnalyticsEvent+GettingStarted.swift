import Foundation

/// Property values of the getting-started funnel (ADR-035 §8). Kept apart from the features'
/// own types, so `Core` depends on no feature: each store maps its types onto these.
extension AnalyticsEvent {
    /// The Onboarding screens `onboarding_step_viewed` reports; the account screen is
    /// `auth_screen_viewed` instead.
    enum OnboardingScreen: String, Sendable {
        case name, birthdate, gender, sports, goals, level, showcase, personalizing
    }

    /// Which way the account screen was opened.
    enum AuthEntry: String, Sendable {
        /// The end of the Onboarding.
        case create
        /// "Se connecter" on the Welcome.
        case signIn = "sign_in"
    }

    enum AuthMethod: String, Sendable {
        case google, apple, email
    }

    /// Why a Sign-in code was refused.
    enum CodeFailure: String, Sendable {
        case incorrect, expired
        case tooManyAttempts = "too_many_attempts"
        case network
    }

    /// The Paywall variant on screen.
    enum PaywallVariant: String, Sendable {
        case a, b, c
    }

    /// Where the Paywall opened (ADR-039 §9): after the Onboarding, or from a lock.
    enum PaywallEntry: String, Sendable {
        case onboarding
        /// « Voir le classement complet avec Premium ».
        case segmentLeaderboard = "segment_leaderboard"
        /// A locked chip of the Leaderboard screen.
        case leaderboardFilter = "leaderboard_filter"
    }

    /// `leaderboard_viewed`'s filter: the sex chip alone, or the other filter (mirrored in
    /// `packages/contracts/src/analytics/catalog.ts`).
    enum LeaderboardViewedFilter: String, Sendable {
        case all, male, female, period, following, age, weight
    }

    enum TrialPeriod: String, Sendable {
        case year, month
    }

    enum PaywallSkipReason: String, Sendable {
        case offersUnavailable = "offers_unavailable"
    }
}
