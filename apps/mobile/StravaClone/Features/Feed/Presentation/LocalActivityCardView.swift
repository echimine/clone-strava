import SwiftUI

/// A local Activity on top of the feed (ADR-031 §14): date, sport, title, provisional distance
/// and moving time, the route from the local points, and a status line. No elevation gain,
/// place, kudos, comments or share. Delete (confirmed) before `processing` and once `failed`;
/// Retry after an API refusal.
struct LocalActivityCardView: View {
    let card: LocalActivityCard
    var onDelete: () -> Void = {}
    var onRetry: () -> Void = {}

    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                header
                Text(card.activity.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                HStack(alignment: .top, spacing: 0) {
                    stat("Distance", ActivityFormatters.distance(card.activity.distance))
                    Divider().frame(height: 36)
                    stat("Temps", ActivityFormatters.duration(.seconds(card.activity.movingTimeS)))
                }
                .padding(.horizontal, -8)
            }
            .padding([.horizontal, .top], Theme.spacing)

            ActivityMapImage(route: card.route, sport: card.activity.sport)

            statusLine
                .padding(.horizontal, Theme.spacing)
                .padding(.bottom, 12)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("localActivityCard")
        .confirmationDialog(
            FeedMessages.deleteConfirmationTitle,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(FeedMessages.delete, role: .destructive, action: onDelete)
            Button(FeedMessages.cancel, role: .cancel) {}
        } message: {
            Text(FeedMessages.deleteConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: ActivityFormatters.sportSymbol(card.activity.sport))
            Text(ActivityFormatters.sportLabel(card.activity.sport))
            Text("·")
            Text(ActivityFormatters.relativeDateTime(card.activity.startedAt))
            Spacer(minLength: 0)
            if card.activity.canBeDeleted || card.activity.canBeRetried {
                actionsMenu
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var actionsMenu: some View {
        Menu {
            if card.activity.canBeRetried {
                Button(FeedMessages.retry, systemImage: "arrow.clockwise", action: onRetry)
            }
            if card.activity.canBeDeleted {
                Button(FeedMessages.delete, systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .accessibilityLabel("Actions")
        .accessibilityIdentifier("localActivityCard.actions")
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(FeedMessages.status(card.status))
                .font(.subheadline)
                .foregroundStyle(isFailed ? Color.red : .secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if card.activity.canBeRetried {
                Button(FeedMessages.retry, action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("localActivityCard.retry")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("localActivityCard.status")
    }

    @ViewBuilder private var statusIcon: some View {
        switch card.status {
        case .sending, .processing:
            ProgressView().controlSize(.small)
        case .waitingForNetwork:
            Image(systemName: "wifi.slash").foregroundStyle(.secondary)
        case .retryingSoon:
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private var isFailed: Bool {
        if case .failed = card.status { true } else { false }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}
