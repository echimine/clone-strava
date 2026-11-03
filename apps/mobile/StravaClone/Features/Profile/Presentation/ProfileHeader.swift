import SwiftUI

/// Top of the profile (ADR-036 §3), laid out as Strava: avatar, name and Activity count, the
/// Streak, the follow counters, which open my lists, and "Modifier le profil".
struct ProfileHeader: View {
    let profile: AthleteProfile
    /// My photo: a tap on the avatar opens its menu (ADR-037 §2).
    let avatar: AvatarEditor
    let onAvatar: () -> Void
    var onFollows: ((AthleteFollowsRequest.Kind) -> Void)?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ProfileIdentity(
                athlete: profile.athlete,
                activityCount: ProfileMessages.activityCount(profile.activityCount),
                nameIdentifier: "profile.name",
                avatarEditor: avatar,
                onAvatarTap: onAvatar
            )
            StreakLabel(weeks: profile.streakWeeks)
            FollowCounters(
                followers: ProfileMessages.followers(profile.followerCount),
                following: ProfileMessages.following(profile.followingCount),
                open: onFollows
            )
            .accessibilityIdentifier("profile.followCounts")
            // "Partager le profil" stays hidden (ADR-036 §3): one full-width button.
            Button(ProfileMessages.editProfile, action: onEdit)
                .buttonStyle(.profileOutline)
                .accessibilityIdentifier("profile.edit")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    ProfileHeader(
        profile: AthleteProfile(
            athlete: ActivityAuthor(id: "me", displayName: "Camille Martin", avatarURL: nil),
            activityCount: 42,
            streakWeeks: 5,
            followerCount: 12,
            followingCount: 8,
            viewerFollowStatus: nil,
            followersYouKnow: [],
            practicedSports: [.run],
            approveFollowers: false,
            pendingFollowRequestCount: 0,
            itineraryCount: 3
        ),
        avatar: .preview,
        onAvatar: {},
        onEdit: {}
    )
    .padding()
    .tint(Theme.accent)
}
#endif
