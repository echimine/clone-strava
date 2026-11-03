import SwiftUI

/// Top of the profile (ADR-036 §3): avatar in initials, name, Activity count and Streak, the
/// follow counters (their lists come later), and "Modifier le profil".
struct ProfileHeader: View {
    let profile: AthleteProfile
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Theme.spacing) {
                AvatarView(name: profile.athlete.displayName, url: profile.athlete.avatarURL, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.athlete.displayName)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .accessibilityIdentifier("profile.name")
                    Text(ProfileMessages.activityCount(profile.activityCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ProfileMessages.streak(profile.streakWeeks))
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text("\(ProfileMessages.followers(profile.followerCount)) • \(ProfileMessages.following(profile.followingCount))")
                .font(.subheadline)
                .monospacedDigit()
                .accessibilityIdentifier("profile.followCounts")
            Button(ProfileMessages.editProfile, action: onEdit)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
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
        onEdit: {}
    )
    .padding()
    .tint(Theme.accent)
}
#endif
