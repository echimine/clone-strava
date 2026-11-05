#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (voir ActivityResultsProto.swift). Les trois variantes.

private enum ProtoResultItem: Identifiable {
    case segment(ProtoSegmentResult), record(ProtoRecordResult)

    var id: String {
        switch self {
        case .segment(let segment): "s\(segment.id)"
        case .record(let record): "r\(record.label)"
        }
    }

    var medal: Int? {
        switch self {
        case .segment(let segment): segment.medal
        case .record(let record): record.medal
        }
    }

    var isSegment: Bool { if case .segment = self { true } else { false } }

    /// Or, argent, bronze, puis le reste ; les Segments d'abord à Médaille égale, l'ordre de la trace sinon.
    @MainActor static func ranked(_ state: ProtoResultsState) -> [ProtoResultItem] {
        let items = state.segments.map(ProtoResultItem.segment) + state.records.map(ProtoResultItem.record)
        return items.enumerated().sorted { lhs, rhs in
            let left = lhs.element.medal ?? 9, right = rhs.element.medal ?? 9
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

private struct ProtoResultItemRow: View {
    let state: ProtoResultsState
    let item: ProtoResultItem
    var onSelect: (() -> Void)?

    var body: some View {
        switch item {
        case .segment(let segment): ProtoSegmentResultRow(state: state, segment: segment, onSelect: onSelect)
        case .record(let record): ProtoRecordResultRow(state: state, record: record)
        }
    }
}

private struct ProtoCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(Theme.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

// MARK: - A — Section « Résultats » à la Strava, sous les chiffres

struct ProtoResultsVariantA: View {
    let state: ProtoResultsState

    var body: some View {
        if !state.isEmpty {
            let items = ProtoResultItem.ranked(state)
            ProtoCard {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill").foregroundStyle(LinearGradient(colors: ProtoMedal.gradients[0], startPoint: .top, endPoint: .bottom))
                    Text("Résultats").font(.headline)
                }
                ProtoCounters(state: state)
                Divider()
                if state.isMatching { ProtoMatchingRow() }
                ForEach(items.prefix(3)) { item in
                    ProtoResultItemRow(state: state, item: item)
                }
                ProtoPrivacyNote(state: state)
                if items.count > 3 || state.isMatching {
                    NavigationLink(value: ProtoResultsRoute.all) {
                        Text("Afficher tous les résultats (\(items.count))")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

// MARK: - B — Segments et Records séparés

/// Sous le titre : les Médailles par couleur et les deux compteurs.
struct ProtoResultsBMedalLine: View {
    let state: ProtoResultsState

    var body: some View {
        if !state.isEmpty {
            HStack(spacing: 10) {
                ForEach(1...3, id: \.self) { place in
                    let count = state.medals(place)
                    if count > 0 {
                        HStack(spacing: 3) { ProtoMedal(place: place, size: 18); Text("\(count)").font(.subheadline.weight(.semibold)) }
                    }
                }
                Text(summary).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if state.sport == .ride { parts.append(state.isMatching ? "Segments…" : "\(state.segments.count) Segments") }
        parts.append("\(state.records.count) Records")
        return parts.joined(separator: " · ")
    }
}

/// Après les Kudos : tous les Segments dans l'ordre de la trace, numérotés comme sur la carte.
struct ProtoResultsBSegments: View {
    let state: ProtoResultsState

    var body: some View {
        if state.sport == .ride, state.hasResults {
            VStack(alignment: .leading, spacing: 8) {
                Text("Segments").font(.title3.weight(.bold))
                ProtoCard {
                    if state.isMatching { ProtoMatchingRow() }
                    ForEach(Array(state.segments.enumerated()), id: \.element.id) { index, segment in
                        if index > 0 { Divider() }
                        ProtoSegmentResultRow(state: state, segment: segment, number: index + 1)
                    }
                    ProtoPrivacyNote(state: state)
                }
            }
        }
    }
}

/// Juste avant les Splits : un tableau des distances de Record parcourues.
struct ProtoResultsBRecords: View {
    let state: ProtoResultsState

    var body: some View {
        if !state.records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Records").font(.title3.weight(.bold))
                if state.sport == .pool {
                    Text("Piscine · bassin de 25 m").font(.footnote).foregroundStyle(.secondary)
                }
                ProtoCard {
                    HStack {
                        Text("Distance").frame(width: 80, alignment: .leading)
                        Text("Temps").frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("Trophée")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(state.records) { record in
                        HStack {
                            Text(record.label).font(.subheadline.weight(.semibold)).frame(width: 80, alignment: .leading)
                            Text(ProtoFicheData.time(record.seconds)).font(.subheadline).monospacedDigit().frame(width: 80, alignment: .leading)
                            if record.isFirstTime {
                                Text("1re fois").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.15), in: Capsule()).foregroundStyle(Theme.accent)
                            }
                            Spacer()
                            if let medal = record.medal { ProtoMedal(place: medal, size: 22) } else { Text("—").foregroundStyle(.tertiary) }
                        }
                        .contentShape(.rect)
                        .contextMenu {
                            if state.isMine {
                                Button("Retirer ce temps de mes Records", systemImage: "minus.circle", role: .destructive) { state.remove(record) }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - C — Onglets Aperçu | Résultats sous la carte

struct ProtoResultsCTabs: View {
    @Bindable var state: ProtoResultsState

    var body: some View {
        if !state.isEmpty {
            Picker("Vue", selection: $state.tab) {
                Text("Aperçu").tag(0)
                Text("Résultats · \(state.medalCount) 🏆").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.spacing)
        }
    }
}

struct ProtoResultsCList: View {
    let state: ProtoResultsState
    @State private var filter = "Tout"

    var body: some View {
        let filters = state.sport == .ride ? ["Tout", "Trophées", "Segments", "Records"] : ["Tout", "Trophées"]
        let items = ProtoResultItem.ranked(state).filter { item in
            switch filter {
            case "Trophées": item.medal != nil
            case "Segments": item.isSegment
            case "Records": !item.isSegment
            default: true
            }
        }
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ProtoCounters(state: state, tiles: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { name in
                        Button(name) { withAnimation { filter = name } }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(filter == name ? Theme.accent : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(filter == name ? .white : .primary)
                    }
                }
            }
            if state.sport == .pool {
                Text("Piscine · bassin de 25 m").font(.footnote).foregroundStyle(.secondary)
            }
            ProtoCard {
                if state.isMatching { ProtoMatchingRow() }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    ProtoResultItemRow(state: state, item: item, onSelect: select(item))
                    if case .segment(let segment) = item, state.selected == segment.id {
                        NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                            Label("Voir le Segment", systemImage: "arrow.right.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.leading, 38)
                    }
                }
                ProtoPrivacyNote(state: state)
            }
            Text("Toucher un Segment le cadre sur la carte ; toucher un badge de la carte ouvre cet onglet.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func select(_ item: ProtoResultItem) -> (() -> Void)? {
        guard case .segment(let segment) = item else { return nil }
        return { withAnimation { state.selected = state.selected == segment.id ? nil : segment.id } }
    }
}
#endif
