import SwiftUI

/// Plus › « Segments » (ADR-039 §15): my starred Segments, with « + » to create one; a row
/// pushes the Segment's sheet (`SegmentRequest`, registered by the profile's stack).
struct StarredSegmentsView: View {
    @State private var store: StarredSegmentsStore
    let onCreate: () -> Void

    init(makeStore: @MainActor () -> StarredSegmentsStore, onCreate: @escaping () -> Void) {
        _store = State(initialValue: makeStore())
        self.onCreate = onCreate
    }

    var body: some View {
        content
            .navigationTitle(SegmentMessages.mySegmentsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onCreate) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Créer un Segment")
                    .accessibilityIdentifier("createSegmentFromList")
                }
            }
            // Again each time it shows: back from a creation, the new Segment is there.
            .task { await store.load() }
            .refreshable { await store.load() }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading where store.items.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where store.items.isEmpty:
            ContentUnavailableView {
                Label(SegmentMessages.loadFailed, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        default:
            if store.items.isEmpty {
                ContentUnavailableView {
                    Label(SegmentMessages.emptyTitle, systemImage: "flag.pattern.checkered")
                } description: {
                    Text(SegmentMessages.emptyDescription)
                } actions: {
                    Button("Créer un Segment", action: onCreate)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.items) { segment in
                NavigationLink(value: SegmentRequest(segmentID: segment.id)) {
                    StarredSegmentRowView(row: StarredSegmentRow(segment: segment))
                }
                .accessibilityIdentifier("starredSegment.\(segment.id)")
                .onAppear {
                    if segment.id == store.items.last?.id {
                        Task { await store.loadMore() }
                    }
                }
            }
            if store.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
    }
}

private struct StarredSegmentRowView: View {
    let row: StarredSegmentRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ActivityFormatters.sportSymbol(row.segment.sport.sportType))
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(ActivityFormatters.sportLabel(row.segment.sport.sportType))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.segment.name)
                        .font(.headline)
                        .lineLimit(2)
                    if row.segment.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Vérifié")
                    }
                }
                Text(row.figures)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let best = row.bestTime {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(best)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("Mon record")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }
}
