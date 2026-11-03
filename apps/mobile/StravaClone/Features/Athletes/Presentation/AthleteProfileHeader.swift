import SwiftUI

/// Top of another athlete's profile (ADR-036 §3): avatar, name, Activity count and Streak, the
/// counters after the avatars of up to 2 of their followers the viewer follows too, then the
/// follow button. Each counter opens its list.
struct AthleteProfileHeader<FollowButtonContent: View>: View {
    let profile: AthleteProfile
    var onFollows: ((AthleteFollowsRequest.Kind) -> Void)?
    @ViewBuilder let followButton: () -> FollowButtonContent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ProfileIdentity(
                athlete: profile.athlete,
                activityCount: AthletesMessages.activityCount(profile.activityCount),
                nameIdentifier: "athleteProfile.name"
            )
            StreakLabel(weeks: profile.streakWeeks)
            HStack(spacing: 8) {
                if !profile.followersYouKnow.isEmpty {
                    KudosAvatarStack(givers: profile.followersYouKnow, size: 24, ring: Color(.systemBackground))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(AthletesMessages.followersYouKnow(profile.followersYouKnow)))
                }
                FollowCounters(
                    followers: AthletesMessages.followers(profile.followerCount),
                    following: AthletesMessages.following(profile.followingCount),
                    open: onFollows
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("athleteProfile.followCounts")
            followButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    AthleteProfileHeader(
        profile: AthleteProfile(
            athlete: ActivityAuthor(id: "lea", displayName: "Léa Bernard", avatarURL: nil),
            activityCount: 128,
            streakWeeks: 3,
            followerCount: 54,
            followingCount: 61,
            viewerFollowStatus: FollowStatus.none,
            followersYouKnow: [
                ActivityAuthor(id: "hugo", displayName: "Hugo Petit", avatarURL: nil),
                ActivityAuthor(id: "ines", displayName: "Inès Moreau", avatarURL: nil),
            ],
            practicedSports: [.run, .ride],
            approveFollowers: nil,
            pendingFollowRequestCount: nil,
            itineraryCount: nil
        )
    ) {
        FollowButton(status: .none, controlSize: .large, onFollow: {}, onUnfollow: {})
            .frame(maxWidth: .infinity)
    }
    .padding()
}
#endif
