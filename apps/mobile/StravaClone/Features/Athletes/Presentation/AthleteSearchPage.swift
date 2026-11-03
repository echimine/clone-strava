import SwiftUI

/// The athlete search (ADR-036 §2), pushed from the profile's magnifier: a search field, then
/// the results with the matched part of each name in bold and a follow button. A tap on an
/// athlete opens their profile through `\.openAthlete`.
struct AthleteSearchPage: View {
    @State private var store: AthleteSearchStore

    init(makeStore: @MainActor () -> AthleteSearchStore) {
        _store = State(initialValue: makeStore())
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle(AthletesMessages.searchTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: Binding(get: { store.query }, set: { store.updateQuery($0) }),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: AthletesMessages.searchPrompt
            )
            .autocorrectionDisabled()
            .toast(Binding(get: { store.follows.toast }, set: { store.follows.toast = $0 }))
            .accessibilityIdentifier("athleteSearch")
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle:
            ContentUnavailableView(
                AthletesMessages.searchPrompt,
                systemImage: "magnifyingglass",
                description: Text(AthletesMessages.searchHint)
            )
        case .searching where store.results.isEmpty:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView(AthletesMessages.errorTitle, systemImage: "wifi.exclamationmark", description: Text(message))
        default:
            if store.isEmpty {
                ContentUnavailableView(
                    AthletesMessages.searchEmptyTitle,
                    systemImage: "person.fill.questionmark",
                    description: Text(AthletesMessages.searchEmptyDescription)
                )
            } else {
                List(store.results) { item in
                    AthleteRow(
                        athlete: item.athlete,
                        name: SearchHighlight.highlighted(item.athlete.displayName, query: store.query)
                    ) {
                        FollowButton.row(athleteId: item.id, store: store.follows)
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }
}
