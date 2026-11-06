import SwiftUI

/// Opening of a Segment's sheet (ADR-039 §15): pushed from the Map's carousel, Plus ›
/// « Segments » and an Activity's « Résultats ».
struct SegmentRequest: Hashable {
    let segmentID: String
}

/// Opening of the athlete search (ADR-036 §2): pushed from the home's magnifier.
struct AthleteSearchRequest: Hashable {}

/// The screens every tab's `NavigationStack` can push (ADR-036 §10): the Activity detail, the
/// Kudos and comments screen, another athlete's profile, Statistiques, the followers and
/// following lists, and a Segment's sheet. Built by the app shell, once per stack, since
/// features never build each other's screens (ADR-007 rule 5); a new destination is added here
/// and in the shell only.
struct AppDestinations {
    let activity: @MainActor (ActivityDetailRequest) -> AnyView
    let engagement: @MainActor (ActivityEngagementRequest) -> AnyView
    let athleteProfile: @MainActor (AthleteProfileRequest) -> AnyView
    let statistics: @MainActor (AthleteStatisticsRequest) -> AnyView
    let follows: @MainActor (AthleteFollowsRequest) -> AnyView
    let segment: @MainActor (SegmentRequest) -> AnyView
    let search: @MainActor (AthleteSearchRequest) -> AnyView

    /// Previews: every destination is empty.
    static let none = AppDestinations(
        activity: { _ in AnyView(EmptyView()) },
        engagement: { _ in AnyView(EmptyView()) },
        athleteProfile: { _ in AnyView(EmptyView()) },
        statistics: { _ in AnyView(EmptyView()) },
        follows: { _ in AnyView(EmptyView()) },
        segment: { _ in AnyView(EmptyView()) },
        search: { _ in AnyView(EmptyView()) }
    )
}

extension View {
    /// Registers every `AppDestinations` screen on the enclosing `NavigationStack`.
    func registerAppDestinations(_ destinations: AppDestinations) -> some View {
        navigationDestination(for: ActivityDetailRequest.self) { destinations.activity($0) }
            .navigationDestination(for: ActivityEngagementRequest.self) { destinations.engagement($0) }
            .navigationDestination(for: AthleteProfileRequest.self) { destinations.athleteProfile($0) }
            .navigationDestination(for: AthleteStatisticsRequest.self) { destinations.statistics($0) }
            .navigationDestination(for: AthleteFollowsRequest.self) { destinations.follows($0) }
            .navigationDestination(for: SegmentRequest.self) { destinations.segment($0) }
            .navigationDestination(for: AthleteSearchRequest.self) { destinations.search($0) }
    }
}
