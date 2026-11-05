import SwiftUI

/// Progrès (ADR-036 §4): sport pills that filter the whole tab, "Cette semaine", the 12-week
/// distance chart and the Série card.
struct ProfileProgressTab: View {
    @Bindable var store: ProfileProgressStore
    let practicedSports: [SportType]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if !store.sports.isEmpty {
                SportPills(sports: store.sports, selected: store.sport) { sport in
                    Task { await store.select(sport) }
                }
            }
            content
        }
        .task(id: practicedSports) { await store.load(practicedSports: practicedSports) }
        .accessibilityIdentifier("profile.progress")
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading where store.progress == nil:
            ProgressView()
                .accessibilityLabel("Chargement")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .empty:
            ContentUnavailableView(
                StatisticsMessages.noActivityTitle,
                systemImage: "figure.run",
                description: Text(StatisticsMessages.noActivityMessage)
            )
            .accessibilityIdentifier("profile.progress.empty")
        case .failed(let message):
            ContentUnavailableView {
                Label(StatisticsMessages.progressErrorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(ProfileMessages.retry) { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if let progress = store.progress {
                VStack(spacing: Theme.spacing) {
                    thisWeek(progress)
                    ProgressCard(title: StatisticsMessages.lastTwelveWeeks) {
                        WeeklyDistanceChart(progress: progress, selectedDate: $store.selectedDate)
                        if let week = store.selectedWeek {
                            SelectedWeekSummary(week: week, sport: progress.sport)
                        }
                    }
                    if let month = store.month {
                        StreakCard(weeks: progress.streakWeeks, month: month)
                    }
                }
                .padding(.horizontal, Theme.spacing)
            }
        }
    }

    private func thisWeek(_ progress: AthleteProgress) -> some View {
        ProgressCard(title: StatisticsMessages.thisWeek) {
            if let week = progress.thisWeek {
                WeekValues(week: week, sport: progress.sport)
            }
        }
        .accessibilityIdentifier("profile.progress.thisWeek")
    }
}

/// The sport pills over Progrès: the chosen one filled in `Theme.accent`.
private struct SportPills: View {
    let sports: [SportType]
    let selected: SportType?
    let select: (SportType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sports, id: \.self) { sport in
                    let isSelected = sport == selected
                    Button { select(sport) } label: {
                        Label(ActivityFormatters.sportLabel(sport), systemImage: ActivityFormatters.sportSymbol(sport))
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(
                                isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("profile.progress.sport.\(sport.code)")
                }
            }
            .padding(.horizontal, Theme.spacing)
        }
    }
}

/// A rounded card of the Progrès tab with its title.
private struct ProgressCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

/// Distance, Dénivelé (when the sport tracks it) and Temps of one week.
private struct WeekValues: View {
    let week: WeekProgress
    let sport: SportType

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            value(StatisticsMessages.distance, ActivityFormatters.distance(week.distance))
            if sport.tracksElevation {
                value(StatisticsMessages.elevation, ActivityFormatters.elevation(week.elevationGain))
            }
            value(StatisticsMessages.time, ActivityFormatters.duration(week.movingTime))
        }
    }

    private func value(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The touched week under the chart: its dates, then its values.
private struct SelectedWeekSummary: View {
    let week: WeekProgress
    let sport: SportType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = week.weekStart.startInParis {
                Text(StatisticsMessages.weekOf(date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            WeekValues(week: week, sport: sport)
        }
        .accessibilityIdentifier("profile.progress.selectedWeek")
    }
}

/// Série: the number of weeks, then this month's calendar with the active days filled and
/// today circled.
private struct StreakCard: View {
    let weeks: Int
    let month: StreakMonth

    private static let weekdays = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        ProgressCard(title: StatisticsMessages.streak) {
            Text(StatisticsMessages.streakWeeks(weeks))
                .font(.title2.weight(.bold))
                .monospacedDigit()
            if let first = CalendarDay(year: month.year, month: month.month, day: 1).startInParis {
                Text(StatisticsMessages.month(first).capitalized(with: ActivityFormatters.locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    ForEach(Self.weekdays.indices, id: \.self) { index in
                        Text(Self.weekdays[index])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                ForEach(month.weeks.indices, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            DayCell(cell: month.weeks[row][column])
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("profile.progress.streak")
    }
}

private struct DayCell: View {
    let cell: StreakMonth.Cell?

    var body: some View {
        ZStack {
            if let cell {
                if cell.isActive {
                    Circle().fill(Theme.accent)
                }
                if cell.isToday {
                    Circle().strokeBorder(cell.isActive ? Color.primary : Theme.accent, lineWidth: 2)
                }
                Text("\(cell.day)")
                    .font(.footnote.weight(cell.isActive || cell.isToday ? .semibold : .regular))
                    .foregroundStyle(cell.isActive ? Color.white : Color.primary)
                    .monospacedDigit()
            }
        }
        .frame(width: 32, height: 32)
        .frame(maxWidth: .infinity)
        .modifier(DayCellAccessibility(cell: cell))
    }
}

/// A day of the Série calendar: its number, "actif" when an Activity was done, "aujourd'hui".
private struct DayCellAccessibility: ViewModifier {
    let cell: StreakMonth.Cell?

    func body(content: Content) -> some View {
        if let cell {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(cell.day)")
                .accessibilityValue([
                    cell.isActive ? "actif" : "inactif",
                    cell.isToday ? "aujourd'hui" : nil,
                ].compactMap { $0 }.joined(separator: ", "))
        } else {
            content.accessibilityHidden(true)
        }
    }
}
