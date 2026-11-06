import SwiftUI

/// The Local Legend (ADR-039 §8): laurel crown, Avatar, name, « N Efforts ces 90 derniers
/// jours », then, on the sheet, how many more I need.
struct LocalLegendCard: View {
    let legend: LocalLegend
    /// My id, known from my line; nil when I have none.
    let viewerID: String?
    /// « Toi : n Efforts. Encore k… », on the sheet only (Tous).
    let showsMine: Bool

    var body: some View {
        if let holder = legend.holder {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Image(systemName: "laurel.leading").font(.system(size: 30)).foregroundStyle(.orange)
                        AvatarView(name: holder.athlete.displayName, url: holder.athlete.avatarURL, size: 44)
                        Image(systemName: "laurel.trailing").font(.system(size: 30)).foregroundStyle(.orange)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SegmentMessages.localLegend)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(holder.athlete.id == viewerID ? SegmentMessages.you : holder.athlete.displayName)
                            .font(.headline)
                        Text(SegmentMessages.legendEfforts(holder.effortCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if showsMine, let mine = legend.myEffortCount, let missing = legend.effortsToTakeIt(viewerID: viewerID ?? "") {
                    Text(SegmentMessages.toTakeTheLegend(mine: mine, missing: missing))
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("localLegend")
        } else {
            Text(SegmentMessages.noLocalLegend)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("localLegend.none")
        }
    }
}

/// One line: rank, Avatar, name, date, time; mine highlighted « (toi) ».
struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let isMine: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(entry.rank)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 32, alignment: .leading)
            AvatarView(name: entry.athlete.displayName, url: entry.athlete.avatarURL, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMine ? SegmentMessages.meLabel(entry.athlete.displayName) : entry.athlete.displayName)
                    .font(.subheadline.weight(isMine ? .bold : .regular))
                    .lineLimit(1)
                Text(SegmentMessages.date(entry.startedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(SegmentMessages.time(entry.elapsedSeconds))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, isMine ? 8 : 0)
        .background(isMine ? Theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// The lines, my line pinned under them when I am further, and, without Premium, the insert.
struct LeaderboardRows: View {
    let leaderboard: Leaderboard
    let showsPremiumInsert: Bool
    let onPremiumInsert: () -> Void
    var onLastAppeared: () -> Void = {}

    var body: some View {
        LazyVStack(spacing: 0) {
            if leaderboard.entries.isEmpty {
                Text(SegmentMessages.nobodyInFilter)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            ForEach(leaderboard.entries) { entry in
                LeaderboardRow(entry: entry, isMine: leaderboard.isMine(entry))
                    .onAppear { if entry.id == leaderboard.entries.last?.id { onLastAppeared() } }
                Divider()
            }
            if let me = leaderboard.pinnedMe {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
                LeaderboardRow(entry: me, isMine: true)
                    .accessibilityIdentifier("leaderboard.pinnedMe")
            }
            if showsPremiumInsert, leaderboard.limited {
                PremiumInsert(athleteCount: leaderboard.athleteCount, action: onPremiumInsert)
                    .padding(.top, 12)
            }
        }
    }
}

/// « Voir le classement complet avec Premium »: the athletes and the filters it opens.
private struct PremiumInsert: View {
    let athleteCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SegmentMessages.premiumInsertTitle).font(.subheadline.weight(.semibold))
                    Text(SegmentMessages.premiumInsertDetail(athletes: athleteCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leaderboard.premiumInsert")
    }
}

/// A filter chip of the Leaderboard screen; a lock without Premium.
struct LeaderboardChip: View {
    let title: String
    let isOn: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLocked { Image(systemName: "lock.fill") }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? .white : .primary)
            .background(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.regularMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isLocked ? "Premium" : "")
    }
}
