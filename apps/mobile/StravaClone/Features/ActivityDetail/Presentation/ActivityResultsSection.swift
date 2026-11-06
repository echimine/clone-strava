import SwiftUI

/// « Résultats » of the detail (ADR-039 §15, spec #252), a card like the Splits', just before
/// them: three counters, at most 3 medalled lines, « Afficher tous les résultats ». Nothing
/// without a result.
struct ActivityResultsSection: View {
    let store: ActivityResultsStore
    let detail: ActivityDetail

    @State private var showsAll = false

    var body: some View {
        if let results = store.results {
            let summary = ActivityResultsSummary(results: results, sport: detail.sport)
            if !summary.isEmpty {
                ActivityAnalysisCard(title: ActivityResultsMessages.title) {
                    VStack(alignment: .leading, spacing: 18) {
                        ActivityResultsCounters(counters: summary.counters)
                        ForEach(summary.lines) { line in
                            ActivityResultRow(line: line, store: store)
                        }
                        if summary.showsMatching {
                            ActivityResultsMatchingRow()
                        }
                        Button {
                            showsAll = true
                        } label: {
                            Text(ActivityResultsMessages.showAll)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("activityResults.showAll")
                    }
                }
                .accessibilityIdentifier("activityResults")
                .navigationDestination(isPresented: $showsAll) {
                    ActivityResultsPage(store: store, detail: detail)
                }
            }
        }
    }
}

/// Meilleurs efforts · Segments · Performances, the label above the number.
struct ActivityResultsCounters: View {
    let counters: [ActivityResultsSummary.Counter]

    var body: some View {
        HStack(alignment: .top) {
            ForEach(counters, id: \.label) { counter in
                VStack(spacing: 4) {
                    Text(counter.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(counter.value)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// One line: the medal (or a blank of its width), the title, the figures, the phrase. A Segment
/// opens its sheet; the author's Best effort can be removed with a long press.
struct ActivityResultRow: View {
    let line: ActivityResultLine
    let store: ActivityResultsStore

    var body: some View {
        switch line.target {
        case .segment(let segmentID):
            NavigationLink(value: SegmentRequest(segmentID: segmentID)) {
                ActivityResultLineView(line: line)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activityResults.segment")
        case .bestEffort:
            ActivityResultLineView(line: line)
                .contextMenu {
                    if line.removable, let effort = store.bestEffort(for: line) {
                        Button(ActivityResultsMessages.remove, systemImage: "minus.circle", role: .destructive) {
                            store.removalCandidate = effort
                        }
                    }
                }
                .accessibilityIdentifier("activityResults.bestEffort")
        }
    }
}

struct ActivityResultLineView: View {
    let line: ActivityResultLine

    private static let medalSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let medal = line.medal {
                MedalRibbon(medal, size: Self.medalSize)
            } else {
                Color.clear.frame(width: Self.medalSize, height: Self.medalSize)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(line.title)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    if line.localLegend {
                        Image(systemName: "laurel.leading")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(ActivityResultsMessages.localLegend)
                    }
                }
                HStack(spacing: 14) {
                    ForEach(line.figures, id: \.self) { Text($0) }
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                if let note = line.note {
                    Text(note).font(.subheadline)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// While the Segments are looked for.
struct ActivityResultsMatchingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(ActivityResultsMessages.matching)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activityResults.matching")
    }
}

extension View {
    /// The confirmation of « Retirer ce temps de mes meilleurs efforts », and its notice.
    func bestEffortRemoval(_ store: ActivityResultsStore?) -> some View {
        modifier(BestEffortRemoval(store: store))
    }
}

private struct BestEffortRemoval: ViewModifier {
    let store: ActivityResultsStore?

    func body(content: Content) -> some View {
        if let store {
            @Bindable var store = store
            content
                .confirmationDialog(
                    ActivityResultsMessages.removeConfirmTitle,
                    isPresented: Binding(
                        get: { store.removalCandidate != nil },
                        set: { if !$0 { store.removalCandidate = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: store.removalCandidate
                ) { effort in
                    Button(ActivityResultsMessages.removeConfirm, role: .destructive) {
                        Task { await store.remove(effort) }
                    }
                } message: { _ in
                    Text(ActivityResultsMessages.removeMessage)
                }
                .toast($store.notice)
        } else {
            content
        }
    }
}
