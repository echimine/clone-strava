import SwiftUI

/// Statistiques (ADR-036 §4) of any athlete: a sport picker with icons, then a full-width
/// list under grey uppercase headers — ACTIVITÉ, DEPUIS LE DÉBUT DE L'ANNÉE, DE TOUT TEMPS.
/// Pushed by the app shell for an `AthleteStatisticsRequest`, from my Plus tab or another
/// athlete's.
struct AthleteStatisticsView: View {
    @State private var store: AthleteStatisticsStore

    init(store: AthleteStatisticsStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        List {
            if !store.sports.isEmpty {
                Section {
                    SportIconPicker(sports: store.sports, selected: store.sport) { sport in
                        Task { await store.select(sport) }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: Theme.spacing, bottom: 12, trailing: Theme.spacing))
                }
            }
            content
        }
        .listStyle(.grouped)
        .navigationTitle(StatisticsMessages.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.retry() }
        .accessibilityIdentifier("statistics.page")
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading where store.stats == nil:
            Section {
                ProgressView().frame(maxWidth: .infinity)
            }
        case .failed(let message):
            Section {
                ContentUnavailableView {
                    Label(StatisticsMessages.errorTitle, systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button(ProfileMessages.retry) { Task { await store.retry() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        default:
            if let stats = store.stats {
                ForEach(AthleteStatisticsSection.sections(for: stats)) { section in
                    Section {
                        ForEach(section.rows, id: \.label) { row in
                            LabeledContent(row.label) {
                                Text(row.value)
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if section.title == StatisticsMessages.recentTitle {
                            Text(StatisticsMessages.recentFooter)
                        }
                    }
                }
            }
        }
    }
}

/// The Statistiques' sport picker: one round icon per sport, the chosen one in `Theme.accent`.
private struct SportIconPicker: View {
    let sports: [SportType]
    let selected: SportType?
    let select: (SportType) -> Void

    var body: some View {
        HStack(spacing: Theme.spacing) {
            ForEach(sports, id: \.self) { sport in
                let isSelected = sport == selected
                Button { select(sport) } label: {
                    Image(systemName: ActivityFormatters.sportSymbol(sport))
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(
                            isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: .circle
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ActivityFormatters.sportLabel(sport))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("statistics.sport.\(sport.code)")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(StatisticsMessages.sportPicker)
    }
}
