import Foundation

/// Typed catalog of the events the app sends (ADR-015): `object_action` names in the past
/// tense, no free-form strings in the code. Itinerary journey events follow issue #20 and
/// ADR-030 §10; the API sends the lifecycle ones. Properties are rounded and never hold a
/// coordinate: `AnalyticsValue` has no floating-point case. `itineraryId` is the id the app
/// generates, the one the API events carry too.
///
/// The getting-started funnel (Welcome, Onboarding, account, Paywall, notification priming;
/// ADR-035 §8) never carries a name, an email or its domain, a birth date or an age, or a
/// gender. Lists are sent as joined strings. Its property types live in
/// `AnalyticsEvent+GettingStarted.swift`.
enum AnalyticsEvent: Equatable, Sendable {
    /// The editor creates a new Itinerary, or reopens a saved one ("Modifier").
    enum EditorMode: String, Sendable {
        case create, edit
    }

    /// Where the editor was opened from.
    enum EditorSource: String, Sendable {
        case mapTab = "map_tab", profile, detail, recording
    }

    /// Where a list or a detail is shown.
    enum ListSource: String, Sendable {
        case mapTab = "map_tab", profile
    }

    enum EditorOutcome: String, Sendable {
        case saved, abandoned
    }

    case itineraryEditorOpened(itineraryId: String, mode: EditorMode, source: EditorSource)
    case itineraryEditorFirstWaypointPlaced(itineraryId: String, sportTypeCode: String)
    /// Gestures are measured by the session counters, not one event each.
    case itineraryEditorClosed(itineraryId: String, outcome: EditorOutcome, hasChanges: Bool, counters: ItineraryEditorCounters)
    /// First `429` from the router in an editor session.
    case itineraryRoutingRateLimited(itineraryId: String)
    case itineraryListViewed(source: ListSource, itineraryCount: Int)
    case itineraryViewed(itineraryId: String, source: ListSource, offline: Bool)
    /// "Créer" or "Modifier" offline: "Connexion requise".
    case itineraryOfflineEditBlocked(action: EditorMode)

    /// The Welcome is on screen, once the splash is gone.
    case welcomeViewed
    /// "Créer un compte" on the Welcome.
    case onboardingStarted
    /// Each screen of the Onboarding; `resumed` on the first screen after a resumed draft.
    case onboardingStepViewed(step: OnboardingScreen, resumed: Bool)
    /// "Créer mon compte": codes sorted and joined, `goalsCount` 0 when the goals were skipped.
    case onboardingCompleted(sportCodes: [String], goals: [String], level: String)
    case authScreenViewed(entry: AuthEntry)
    /// "Continuer avec Google", or "Continuer" under the email.
    case authMethodChosen(method: AuthMethod)
    case authGoogleCancelled
    /// A Sign-in code was sent; `resend` for "Recevoir un nouveau code".
    case emailCodeRequested(resend: Bool)
    case emailCodeFailed(reason: CodeFailure)
    /// A session exists. `isNewAccount` also when "Se connecter" created the account.
    case signedIn(method: AuthMethod, isNewAccount: Bool)
    case paywallViewed(layout: PaywallVariant, isNewAccount: Bool)
    /// Left without being shown: its offers could not be loaded.
    case paywallSkipped(reason: PaywallSkipReason)
    /// "Démarrer l'essai".
    case paywallTrialTapped(layout: PaywallVariant, period: TrialPeriod)
    /// "Passer" / "Non merci".
    case paywallDismissed(layout: PaywallVariant)
    /// Nervo's notification priming screen is shown.
    case notificationPromptViewed
    /// The answer in iOS's own prompt, never a step skipped.
    case notificationPermissionAnswered(granted: Bool)
    /// "Plus tard" on the priming screen.
    case notificationPermissionDeferred

    /// A Media tile turned "Échec" (ADR-037 §13): no id, no image data.
    case mediaUploadFailed(kind: ActivityMedia.Kind, reason: MediaUploadFailure)
    /// "Enregistrer" with the Media changed, once per session (ADR-037 §13): nothing for a
    /// session unchanged or cancelled.
    case activityMediaSaved(entry: ActivityMediaSavedEntry, ActivityMediaSaved)
    /// A new Avatar is stored (ADR-037 §13). Never any image data.
    case avatarChanged(source: AvatarSource, entry: AvatarEntry)
    /// "Supprimer la photo" went through.
    case avatarRemoved
    /// The Avatar was not sent, or not stored.
    case avatarUploadFailed(reason: AvatarUploadFailure)
    /// "Ajoute une photo de profil" is shown, before the Paywall.
    case avatarPromptViewed
    /// "Plus tard" on that screen.
    case avatarPromptDeferred

    /// The full-screen viewer opened on a Media (ADR-037 §13); its swipes are not tracked.
    case mediaViewerOpened(source: MediaViewerSource, kind: ActivityMedia.Kind, isOwn: Bool)
    /// The profile's Galerie tab opened, mine or another athlete's.
    case galleryViewed(isOwn: Bool)
    /// An athlete blocked another one (ADR-038 §8), never with their id.
    case athleteBlocked(source: BlockSource)
    /// "Débloquer" confirmed in Réglages > "Athlètes bloqués", never with the athlete's id.
    case athleteUnblocked
    /// A Segment starred (ADR-039 §16), from a Map card or its sheet; no property.
    case segmentFavorited

    var name: String {
        switch self {
        case .itineraryEditorOpened: "itinerary_editor_opened"
        case .itineraryEditorFirstWaypointPlaced: "itinerary_editor_first_waypoint_placed"
        case .itineraryEditorClosed: "itinerary_editor_closed"
        case .itineraryRoutingRateLimited: "itinerary_routing_rate_limited"
        case .itineraryListViewed: "itinerary_list_viewed"
        case .itineraryViewed: "itinerary_viewed"
        case .itineraryOfflineEditBlocked: "itinerary_offline_edit_blocked"
        case .welcomeViewed: "welcome_viewed"
        case .onboardingStarted: "onboarding_started"
        case .onboardingStepViewed: "onboarding_step_viewed"
        case .onboardingCompleted: "onboarding_completed"
        case .authScreenViewed: "auth_screen_viewed"
        case .authMethodChosen: "auth_method_chosen"
        case .authGoogleCancelled: "auth_google_cancelled"
        case .emailCodeRequested: "email_code_requested"
        case .emailCodeFailed: "email_code_failed"
        case .signedIn: "signed_in"
        case .paywallViewed: "paywall_viewed"
        case .paywallSkipped: "paywall_skipped"
        case .paywallTrialTapped: "paywall_trial_tapped"
        case .paywallDismissed: "paywall_dismissed"
        case .notificationPromptViewed: "notification_prompt_viewed"
        case .notificationPermissionAnswered: "notification_permission_answered"
        case .notificationPermissionDeferred: "notification_permission_deferred"
        case .mediaUploadFailed: "media_upload_failed"
        case .activityMediaSaved: "activity_media_saved"
        case .avatarChanged: "avatar_changed"
        case .avatarRemoved: "avatar_removed"
        case .avatarUploadFailed: "avatar_upload_failed"
        case .avatarPromptViewed: "avatar_prompt_viewed"
        case .avatarPromptDeferred: "avatar_prompt_deferred"
        case .mediaViewerOpened: "media_viewer_opened"
        case .galleryViewed: "gallery_viewed"
        case .athleteBlocked: "athlete_blocked"
        case .athleteUnblocked: "athlete_unblocked"
        case .segmentFavorited: "segment_favorited"
        }
    }

    var properties: [String: AnalyticsValue] {
        switch self {
        case .itineraryEditorOpened(let id, let mode, let source):
            ["itineraryId": .string(id), "mode": .string(mode.rawValue), "source": .string(source.rawValue)]
        case .itineraryEditorFirstWaypointPlaced(let id, let sportTypeCode):
            ["itineraryId": .string(id), "sportTypeCode": .string(sportTypeCode)]
        case .itineraryEditorClosed(let id, let outcome, let hasChanges, let counters):
            counters.properties.merging([
                "itineraryId": .string(id),
                "outcome": .string(outcome.rawValue),
                "hasChanges": .bool(hasChanges),
            ]) { _, new in new }
        case .itineraryRoutingRateLimited(let id):
            ["itineraryId": .string(id)]
        case .itineraryListViewed(let source, let count):
            ["source": .string(source.rawValue), "itineraryCount": .int(count)]
        case .itineraryViewed(let id, let source, let offline):
            ["itineraryId": .string(id), "source": .string(source.rawValue), "offline": .bool(offline)]
        case .itineraryOfflineEditBlocked(let action):
            ["action": .string(action.rawValue)]
        case .welcomeViewed, .onboardingStarted, .authGoogleCancelled, .notificationPromptViewed,
             .notificationPermissionDeferred, .avatarRemoved, .avatarPromptViewed, .avatarPromptDeferred,
             .segmentFavorited:
            [:]
        case .onboardingStepViewed(let step, let resumed):
            ["step": .string(step.rawValue), "resumed": .bool(resumed)]
        case .onboardingCompleted(let sportCodes, let goals, let level):
            [
                "sportCodes": .string(sportCodes.sorted().joined(separator: ",")),
                "goals": .string(goals.sorted().joined(separator: ",")),
                "goalsCount": .int(goals.count),
                "level": .string(level),
            ]
        case .authScreenViewed(let entry):
            ["entry": .string(entry.rawValue)]
        case .authMethodChosen(let method):
            ["method": .string(method.rawValue)]
        case .emailCodeRequested(let resend):
            ["resend": .bool(resend)]
        case .emailCodeFailed(let reason):
            ["reason": .string(reason.rawValue)]
        case .signedIn(let method, let isNewAccount):
            ["method": .string(method.rawValue), "isNewAccount": .bool(isNewAccount)]
        case .paywallViewed(let layout, let isNewAccount):
            ["layout": .string(layout.rawValue), "isNewAccount": .bool(isNewAccount)]
        case .paywallSkipped(let reason):
            ["reason": .string(reason.rawValue)]
        case .paywallTrialTapped(let layout, let period):
            ["layout": .string(layout.rawValue), "period": .string(period.rawValue)]
        case .paywallDismissed(let layout):
            ["layout": .string(layout.rawValue)]
        case .notificationPermissionAnswered(let granted):
            ["granted": .bool(granted)]
        case .mediaUploadFailed(let kind, let reason):
            ["kind": .string(kind.rawValue), "reason": .string(reason.analyticsReason)]
        case .activityMediaSaved(let entry, let saved):
            [
                "entry": .string(entry.rawValue),
                "photosAdded": .int(saved.photosAdded),
                "videosAdded": .int(saved.videosAdded),
                "videosTrimmed": .int(saved.videosTrimmed),
                "mediaRemoved": .int(saved.mediaRemoved),
                "mediaFirst": .bool(saved.mediaFirst),
                "mediaCount": .int(saved.mediaCount),
            ]
        case .avatarChanged(let source, let entry):
            ["source": .string(source.rawValue), "entry": .string(entry.rawValue)]
        case .avatarUploadFailed(let reason):
            ["reason": .string(reason.rawValue)]
        case .mediaViewerOpened(let source, let kind, let isOwn):
            ["source": .string(source.rawValue), "kind": .string(kind.rawValue), "isOwn": .bool(isOwn)]
        case .galleryViewed(let isOwn):
            ["isOwn": .bool(isOwn)]
        case .athleteBlocked(let source):
            ["source": .string(source.rawValue)]
        case .athleteUnblocked:
            ["source": .string("settings")]
        }
    }
}

/// What happened during one editor session, sent when the editor closes (issue #20).
struct ItineraryEditorCounters: Equatable, Sendable {
    var waypointsAdded = 0
    var waypointsMoved = 0
    /// Waypoints inserted by pulling a Leg's middle.
    var waypointsInserted = 0
    var undos = 0
    var redos = 0
    /// Legs the athlete switched to a straight line.
    var legsSwitchedToStraight = 0
    var directionsRequests = 0
    /// Router answers: network failure, timeout or server error.
    var networkFailures = 0
    var noPathResponses = 0
    /// `429` answers.
    var rateLimitedResponses = 0

    fileprivate var properties: [String: AnalyticsValue] {
        [
            "waypointsAdded": .int(waypointsAdded),
            "waypointsMoved": .int(waypointsMoved),
            "waypointsInserted": .int(waypointsInserted),
            "undoCount": .int(undos),
            "redoCount": .int(redos),
            "legsSwitchedToStraight": .int(legsSwitchedToStraight),
            "directionsRequests": .int(directionsRequests),
            "networkFailures": .int(networkFailures),
            "noPathResponses": .int(noPathResponses),
            "rateLimitedResponses": .int(rateLimitedResponses),
        ]
    }
}

/// An event property. Whole numbers only: values are rounded before they get here, and a
/// coordinate cannot be expressed.
enum AnalyticsValue: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case bool(Bool)

    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }

    /// The value as an analytics SDK takes it.
    var plainValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .bool(let value): value
        }
    }
}
