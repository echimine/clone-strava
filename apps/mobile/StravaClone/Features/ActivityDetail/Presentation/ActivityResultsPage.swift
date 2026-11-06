import SwiftUI

/// « Résultats », pushed by « Afficher tous les résultats » (spec #252): every Best effort, with
/// or without a Medal, then every Segment in trace order. A Segment opens its sheet; the author
/// removes a Best effort with a long press.
struct ActivityResultsPage: View {
    let store: ActivityResultsStore
    let detail: ActivityDetail

    var body: some View {
        let results = store.results ?? .empty
        let summary = ActivityResultsSummary(results: results, sport: detail.sport)
        List {
            if !summary.allBestEfforts.isEmpty {
                Section {
                    ForEach(summary.allBestEfforts) { ActivityResultRow(line: $0, store: store) }
                } header: {
                    Text(ActivityResultsMessages.bestEffortsHeader(poolLength: results.poolLength))
                } footer: {
                    if summary.allBestEfforts.contains(where: \.removable) {
                        Text(ActivityResultsMessages.removeHint)
                    }
                }
            }
            if results.poolLength == nil, !summary.allSegments.isEmpty || summary.showsMatching {
                Section {
                    if summary.showsMatching {
                        ActivityResultsMatchingRow()
                    }
                    ForEach(summary.allSegments) { ActivityResultRow(line: $0, store: store) }
                } header: {
                    Text(ActivityResultsMessages.segments)
                } footer: {
                    if !summary.allSegments.isEmpty, let note = ActivityResultsMessages.notOnLeaderboard(
                        detail.visibility,
                        viewerIsAuthor: detail.viewerIsAuthor
                    ) {
                        Label(note, systemImage: "lock")
                    }
                }
            }
        }
        .navigationTitle(ActivityResultsMessages.title)
        .navigationBarTitleDisplayMode(.inline)
        .bestEffortRemoval(store)
        .refreshable { await store.load() }
        .accessibilityIdentifier("activityResults.all")
    }
}
