import SwiftUI

/// The sheet's scrolling content (ADR-039 §15, variant A of the prototype #238).
struct SegmentSheetContent<Leaderboard: View>: View {
    let sheet: SegmentSheet
    /// The Leaderboard screen « Voir le classement » pushes.
    @ViewBuilder let leaderboard: () -> Leaderboard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SegmentTrackMap(track: sheet.track)
                .frame(height: 230)

            VStack(alignment: .leading, spacing: 24) {
                header
                SegmentFacts(sheet: sheet)
                if sheet.track.altitudes.count >= 2 {
                    ElevationProfileChart(profile: sheet.track.elevationProfile)
                        .frame(height: 120)
                }
                if sheet.isMatchingHistory {
                    HistoryMatchingBanner()
                }
                section(SegmentMessages.myEfforts) { MyEffortsSection(sheet: sheet) }
                section(SegmentMessages.localLegend) {
                    LocalLegendCard(legend: sheet.localLegend, viewerID: sheet.leaderboard.me?.athlete.id, showsMine: true)
                }
                section(SegmentMessages.leaderboard) {
                    LeaderboardRows(leaderboard: sheet.leaderboard, showsPremiumInsert: false, onPremiumInsert: {})
                    NavigationLink {
                        leaderboard()
                    } label: {
                        Text(SegmentMessages.seeLeaderboard)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("segmentSheet.seeLeaderboard")
                }
                Text(SegmentMessages.attribution)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(Theme.spacing)
            .padding(.bottom, Theme.spacing * 2)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sheet.name)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                Image(systemName: ActivityFormatters.sportSymbol(sheet.sport))
                Text(ActivityFormatters.sportLabel(sheet.sport))
                if sheet.isVerified {
                    Text("·")
                    Label(SegmentMessages.verified, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// Distance, D+, pente moyenne, catégorie (« — » without one).
private struct SegmentFacts: View {
    let sheet: SegmentSheet

    var body: some View {
        HStack(alignment: .top) {
            fact(ActivityFormatters.distance(sheet.distance), SegmentMessages.distance)
            fact(sheet.elevationGain.map(ActivityFormatters.elevation) ?? "—", SegmentMessages.elevationGain)
            fact(SegmentMessages.grade(sheet.averageGrade), SegmentMessages.averageGrade)
            fact(SegmentMessages.category(sheet.climbCategory), SegmentMessages.category)
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// While the retro-matching of a new Segment runs (ADR-039 §7).
private struct HistoryMatchingBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(SegmentMessages.historyMatching)
                .font(.footnote)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("segmentSheet.historyMatching")
    }
}

/// « Mon record » and « Mon rang », then every Effort of mine, newest first, with its Medal.
private struct MyEffortsSection: View {
    let sheet: SegmentSheet

    var body: some View {
        if sheet.myEfforts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(SegmentMessages.noEffortTitle).font(.headline)
                Text(SegmentMessages.noEffortDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let record = sheet.myRecord {
                    recordRow(record)
                    Divider()
                }
                ForEach(sheet.myEfforts) { effort in
                    effortRow(effort)
                }
            }
        }
    }

    private func recordRow(_ record: MySegmentEffort) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(SegmentMessages.myRecord).font(.caption).foregroundStyle(.secondary)
                Text(SegmentMessages.time(record.elapsedSeconds))
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(SegmentMessages.date(record.startedAt) + (record.isPublicActivity ? "" : " · \(SegmentMessages.privateActivity)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let rank = sheet.myRank {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(SegmentMessages.myRank).font(.caption).foregroundStyle(.secondary)
                    Text(SegmentMessages.rank(rank))
                        .font(.title3.bold())
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("segmentSheet.myRecord")
    }

    private func effortRow(_ effort: MySegmentEffort) -> some View {
        HStack(spacing: 10) {
            Group {
                if let medal = effort.medal {
                    MedalRibbon(medal)
                } else {
                    Color.clear
                }
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(SegmentMessages.date(effort.startedAt)).font(.subheadline)
                if !effort.standing {
                    Label(SegmentMessages.notStanding, systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if effort.isLeaderboardLine, let rank = effort.rank {
                Text(SegmentMessages.rank(rank))
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }
            Text(SegmentMessages.time(effort.elapsedSeconds))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
