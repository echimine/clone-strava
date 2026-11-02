import SwiftUI

/// The Welcome's three full-width scenes (ADR-035 §1), never a phone mock-up.
enum WelcomeScene: Int, CaseIterable, Identifiable {
    case liveActivity, celebration, importFiles

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .liveActivity: "Suivez votre sortie sans déverrouiller."
        case .celebration: "Chaque arrivée se fête."
        case .importFiles: "Retrouvez toutes vos anciennes sorties."
        }
    }

    @ViewBuilder var illustration: some View {
        switch self {
        case .liveActivity: WelcomeLockScreenScene()
        case .celebration: WelcomeCelebrationScene()
        case .importFiles: WelcomeImportScene()
        }
    }
}

/// The Live Activity of a run on the lock screen (ADR-031 §9): it ticks on without unlocking.
private struct WelcomeLockScreenScene: View {
    @State private var start = Date.now.addingTimeInterval(-32 * 60 - 15)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.16, blue: 0.3), Color(red: 0.35, green: 0.2, blue: 0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: 4) {
                    Text("dimanche 8 novembre").font(.subheadline.weight(.semibold)).opacity(0.85)
                    Text("8:42").font(.system(size: 76, weight: .semibold, design: .rounded))
                    Spacer()
                    liveActivity(elapsed: elapsed)
                        .padding(14)
                }
                .padding(.top, 28)
                .foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Écran verrouillé avec une course en cours")
    }

    private func liveActivity(elapsed: TimeInterval) -> some View {
        HStack(spacing: 12) {
            NervoMark()
                .stroke(.white, style: NervoMark.strokeStyle(forSide: 22))
                .frame(width: 22, height: 22)
                .padding(7)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text("Course à pied").font(.caption.weight(.semibold)).opacity(0.75)
                Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f km", elapsed / 310).replacingOccurrences(of: ".", with: ","))
                    .font(.headline.monospacedDigit())
                Text("5:10 /km").font(.caption.monospacedDigit()).opacity(0.75)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.45)))
    }
}

/// The arrival Celebration: the N drawing itself, the distance, a personal record.
private struct WelcomeCelebrationScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.accent
            ForEach(0 ..< 14, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: CGFloat(6 + index % 4 * 3))
                    .offset(x: CGFloat((index * 53) % 260 - 130), y: CGFloat((index * 97) % 300 - 150))
            }
            VStack(spacing: 14) {
                NervoMark()
                    .trim(from: 0, to: draw)
                    .stroke(.white, style: NervoMark.strokeStyle(forSide: 110))
                    .frame(width: 110, height: 110)
                    .accessibilityHidden(true)
                Text("10,0 km").font(.system(size: 44, weight: .heavy, design: .rounded))
                Label("Record perso sur 10 km", systemImage: "medal.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            .foregroundStyle(.white)
        }
        .task {
            guard !reduceMotion else { return draw = 1 }
            while !Task.isCancelled {
                draw = 0
                withAnimation(.easeInOut(duration: 1.1)) { draw = 1 }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

/// Import from a file (ADR-028): years of rides land in Nervo.
private struct WelcomeImportScene: View {
    private struct Row {
        let sport: SportType
        let name: String
        let date: String
        let distance: String
    }

    private static let rows = [
        Row(sport: .ride, name: "Tour du lac", date: "14 juin 2023", distance: "42,3 km"),
        Row(sport: .run, name: "Sortie longue", date: "2 mars 2024", distance: "18,1 km"),
        Row(sport: .hike, name: "Col de la Forclaz", date: "9 août 2025", distance: "11,6 km"),
    ]
    private static let importedCount = 248

    @State private var count = 0

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    ForEach([".gpx", ".fit", ".tcx"], id: \.self) { fileExtension in
                        Text(fileExtension)
                            .font(.caption.weight(.bold).monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().strokeBorder(Color(.separator)))
                    }
                }
                ZStack {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                        card(row)
                            .rotationEffect(.degrees(Double(index - 1) * 3))
                            .offset(y: CGFloat(index) * 58 - 58)
                    }
                }
                .frame(height: 190)
                .padding(.horizontal, 28)
                .accessibilityHidden(true)
                Text("\(count) activités importées")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .task {
            count = 0
            while count < Self.importedCount, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(12))
                withAnimation(.snappy) { count = min(count + 4, Self.importedCount) }
            }
        }
    }

    private func card(_ row: Row) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ActivityFormatters.sportSymbol(row.sport))
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.subheadline.weight(.semibold))
                Text(row.date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.distance).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        )
    }
}
