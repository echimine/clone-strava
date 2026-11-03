import SwiftUI

/// Top of another athlete's profile (ADR-036 §3): avatar, name, Activity count and Streak, the
/// counters after the avatars of up to 2 of their followers the viewer follows too, then the
/// follow button. The counters' lists come later.
struct AthleteProfileHeader<FollowButtonContent: View>: View {
    let profile: AthleteProfile
    @ViewBuilder let followButton: () -> FollowButtonContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Theme.spacing) {
                AvatarView(name: profile.athlete.displayName, url: profile.athlete.avatarURL, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.athlete.displayName)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .accessibilityIdentifier("athleteProfile.name")
                    Text(AthletesMessages.activityCount(profile.activityCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(AthletesMessages.streak(profile.streakWeeks))
                        .font(.subheadline.weight(.semibold))
                }
            }
            HStack(spacing: 8) {
                if !profile.followersYouKnow.isEmpty {
                    KudosAvatarStack(givers: profile.followersYouKnow, size: 24, ring: Color(.systemGroupedBackground))
                }
                Text("\(AthletesMessages.followers(profile.followerCount)) • \(AthletesMessages.following(profile.followingCount))")
                    .font(.subheadline)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(profile.followersYouKnow.isEmpty ? Text("") : Text(AthletesMessages.followersYouKnow(profile.followersYouKnow)))
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
