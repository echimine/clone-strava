import SwiftUI

/// Avatar, name and "195 activités" at the top of a profile (ADR-036 §3). On my own profile,
/// a tap on the avatar opens the photo menu (ADR-037 §2), and the photo being sent shows.
struct ProfileIdentity: View {
    let athlete: ActivityAuthor
    /// "195 activités".
    let activityCount: String
    let nameIdentifier: String
    /// My own profile only.
    var avatarEditor: AvatarEditor?
    var onAvatarTap: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.spacing) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(athlete.displayName)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(nameIdentifier)
                Text(activityCount)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let avatarEditor, let onAvatarTap {
            Button(action: onAvatarTap) {
                EditableAvatar(name: athlete.displayName, url: athlete.avatarURL, editor: avatarEditor)
            }
            .buttonStyle(.plain)
            .disabled(avatarEditor.isBusy)
            .accessibilityLabel(AvatarMessages.myPhoto)
            .accessibilityHint(AvatarMessages.changePhoto)
            .accessibilityIdentifier("profile.avatar")
        } else {
            AvatarView(name: athlete.displayName, url: athlete.avatarURL, size: 76)
        }
    }
}

/// "🔥 24 semaines d'affilée" (ADR-036 §5): the flame in `Theme.accent`, the count in bold.
struct StreakLabel: View {
    let weeks: Int

    var body: some View {
        Label {
            Text("\(Text(weeks.formatted()).fontWeight(.bold)) \(weeks == 1 ? "semaine" : "semaines") d'affilée")
        } icon: {
            Image(systemName: "flame.fill").foregroundStyle(Theme.accent)
        }
        .font(.body)
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }
}

/// "Modifier le profil": a full-width capsule outline.
struct ProfileOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .overlay(Capsule().strokeBorder(Color(.systemGray4), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

extension ButtonStyle where Self == ProfileOutlineButtonStyle {
    static var profileOutline: ProfileOutlineButtonStyle { ProfileOutlineButtonStyle() }
}

/// A row of a profile's Plus tab (ADR-036 §3): a large glyph, the title, the figure under it,
/// a chevron when it opens a screen.
struct ProfileMenuRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A profile tab with cards (Progrès, Activités): the cards stay on the grey of a grouped
    /// list, under the white header (Strava's layout).
    func groupedTabContent() -> some View {
        padding(.vertical, Theme.spacing)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ProfileIdentity(
            athlete: ActivityAuthor(id: "me", displayName: "Camille Martin", avatarURL: nil),
            activityCount: "195 activités",
            nameIdentifier: "preview.name"
        )
        StreakLabel(weeks: 24)
        Button("Modifier le profil") {}.buttonStyle(.profileOutline)
        ProfileMenuRow(title: "Statistiques", subtitle: "Cette année : 1 966,7 km", systemImage: "list.bullet.rectangle")
    }
    .padding()
}
#endif
