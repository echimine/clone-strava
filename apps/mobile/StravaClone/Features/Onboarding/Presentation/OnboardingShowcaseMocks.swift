import SwiftUI

// The animated mocks of "Voici ce qui vous attend": drawn, not real data.

private enum ShowcaseMap {
    /// Light map: land, a park, a lake and a few streets.
    static func draw(_ context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(.systemGray6)))
        context.fill(
            Path(ellipseIn: CGRect(x: size.width * 0.55, y: size.height * 0.08, width: size.width * 0.5, height: size.height * 0.35)),
            with: .color(.green.opacity(0.22))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: -size.width * 0.15, y: size.height * 0.62, width: size.width * 0.5, height: size.height * 0.45)),
            with: .color(.blue.opacity(0.18))
        )
        var streets = Path()
        for x in [0.18, 0.47, 0.8] {
            streets.move(to: CGPoint(x: size.width * x, y: 0))
            streets.addLine(to: CGPoint(x: size.width * (x + 0.08), y: size.height))
        }
        for y in [0.25, 0.55, 0.85] {
            streets.move(to: CGPoint(x: 0, y: size.height * y))
            streets.addLine(to: CGPoint(x: size.width, y: size.height * (y - 0.06)))
        }
        context.stroke(streets, with: .color(Color(.systemBackground)), lineWidth: 5)
    }

    /// A winding loop, in the unit square scaled to `size`.
    static func route(in size: CGSize) -> Path {
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
        var path = Path()
        path.move(to: point(0.15, 0.82))
        path.addCurve(to: point(0.3, 0.35), control1: point(0.05, 0.6), control2: point(0.35, 0.55))
        path.addCurve(to: point(0.7, 0.2), control1: point(0.25, 0.12), control2: point(0.55, 0.1))
        path.addCurve(to: point(0.82, 0.62), control1: point(0.95, 0.3), control2: point(0.7, 0.45))
        path.addCurve(to: point(0.42, 0.8), control1: point(0.95, 0.85), control2: point(0.6, 0.9))
        return path
    }

    static let routeStyle = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
}

private func frenchNumber(_ value: Double, digits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "fr_FR")))
}

private func clock(_ seconds: Double) -> String {
    let whole = Int(seconds)
    return String(format: "%d:%02d", whole / 60, whole % 60)
}

private struct ShowcaseStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 1. Recording: the route draws itself, the stats tick up

struct ShowcaseRecordMock: View {
    let sport: SportType

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let progress = min(1, time.truncatingRemainder(dividingBy: 6) / 5)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8).opacity(0.4 + 0.6 * abs(sin(time * 3)))
                    Text("En cours").font(.caption.weight(.bold))
                    Spacer()
                    Label(ActivityFormatters.sportLabel(sport), systemImage: ActivityFormatters.sportSymbol(sport))
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Canvas { context, size in
                    ShowcaseMap.draw(context, size: size)
                    let drawn = ShowcaseMap.route(in: size).trimmedPath(from: 0, to: max(progress, 0.001))
                    context.stroke(drawn, with: .color(Theme.accent), style: ShowcaseMap.routeStyle)
                    if let tip = drawn.currentPoint {
                        let dot = Path(ellipseIn: CGRect(x: tip.x - 8, y: tip.y - 8, width: 16, height: 16))
                        context.fill(dot, with: .color(.white))
                        context.stroke(dot, with: .color(Theme.accent), lineWidth: 4)
                    }
                }
                HStack {
                    ShowcaseStat(label: "Distance (km)", value: frenchNumber(5.24 * progress, digits: 2))
                    ShowcaseStat(label: "Temps", value: clock(1712 * progress))
                    ShowcaseStat(label: "Allure (/km)", value: "5:27")
                }
                .padding(.vertical, 14)
            }
        }
    }
}

// MARK: - 2. Itinerary: the dashed route marches, the elevation profile fills

struct ShowcaseItineraryMock: View {
    private static let heights: [Double] = [0.2, 0.35, 0.3, 0.55, 0.8, 0.7, 0.9, 0.6, 0.45, 0.5, 0.3, 0.25]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let fill = min(1, time.truncatingRemainder(dividingBy: 5) / 3.5)
            VStack(spacing: 0) {
                Canvas { context, size in
                    ShowcaseMap.draw(context, size: size)
                    context.stroke(
                        ShowcaseMap.route(in: size),
                        with: .color(Theme.accent),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [10, 8], dashPhase: -time * 30)
                    )
                    let start = CGPoint(x: size.width * 0.15, y: size.height * 0.82)
                    let end = CGPoint(x: size.width * 0.42, y: size.height * 0.8)
                    context.fill(Path(ellipseIn: CGRect(x: start.x - 7, y: start.y - 7, width: 14, height: 14)), with: .color(.green))
                    context.draw(Image(systemName: "flag.checkered.circle.fill"), at: end)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("12,4 km").font(.headline)
                        Text("D+ 320 m").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                    Canvas { context, size in
                        var area = Path()
                        area.move(to: CGPoint(x: 0, y: size.height))
                        for (index, height) in Self.heights.enumerated() {
                            area.addLine(to: CGPoint(
                                x: size.width * Double(index) / Double(Self.heights.count - 1),
                                y: size.height * (1 - height)
                            ))
                        }
                        area.addLine(to: CGPoint(x: size.width, y: size.height))
                        area.closeSubpath()
                        context.fill(area, with: .color(Color(.systemGray5)))
                        context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * fill, height: size.height)))
                        context.fill(area, with: .linearGradient(
                            Gradient(colors: [Theme.accent, Theme.accent.opacity(0.4)]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: size.height)
                        ))
                    }
                    .frame(height: 54)
                }
                .padding(14)
            }
        }
    }
}

// MARK: - 3. Feed: a friend's activity gets kudos and a comment

struct ShowcaseFeedMock: View {
    let sport: SportType

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
            let liked = phase > 0.3
            let pop = liked ? max(0, 1 - (phase - 0.3) * 6) : 0
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle().fill(Color.purple.gradient).frame(width: 36, height: 36)
                        .overlay(Text("LB").font(.caption.bold()).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Léa B.").font(.subheadline.weight(.semibold))
                        Text("Aujourd'hui à 8:12").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: ActivityFormatters.sportSymbol(sport)).foregroundStyle(.secondary)
                }
                Text("Sortie du dimanche").font(.headline)
                HStack {
                    ShowcaseStat(label: "km", value: "10,2")
                    ShowcaseStat(label: "Temps", value: "52:14")
                    ShowcaseStat(label: "Allure", value: "5:07")
                }
                Canvas { context, size in
                    ShowcaseMap.draw(context, size: size)
                    context.stroke(ShowcaseMap.route(in: size), with: .color(Theme.accent), style: ShowcaseMap.routeStyle)
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 8) {
                    Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .foregroundStyle(liked ? Theme.accent : .secondary)
                        .scaleEffect(1 + pop * 0.6)
                        .overlay(alignment: .top) {
                            Image(systemName: "heart.fill").foregroundStyle(Theme.accent).font(.caption)
                                .offset(y: -30 * (1 - pop))
                                .opacity(liked ? pop : 0)
                        }
                    Text("\(liked ? 12 : 11) kudos").font(.caption.weight(.semibold)).contentTransition(.numericText())
                    Spacer()
                }
                if phase > 0.55 {
                    Text("Bravo, quel rythme !")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .animation(.snappy, value: phase > 0.55)
            .animation(.snappy, value: liked)
        }
    }
}

// MARK: - 4. Segments: you climb the leaderboard and set a personal record

struct ShowcaseLeaderboardMock: View {
    private struct Row: Identifiable {
        let id: String
        let time: String
    }

    private static let before = [
        Row(id: "Lucas", time: "4:12"), Row(id: "Inès", time: "4:35"),
        Row(id: "Hugo", time: "4:48"), Row(id: "Vous", time: "5:02"),
    ]
    private static let after = [
        Row(id: "Lucas", time: "4:12"), Row(id: "Vous", time: "4:31"),
        Row(id: "Inès", time: "4:35"), Row(id: "Hugo", time: "4:48"),
    ]

    @State private var improved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Montée du Mont Valérien", systemImage: "chart.line.uptrend.xyaxis").font(.subheadline.weight(.semibold))
            Text("1,8 km · 6 %").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(Array((improved ? Self.after : Self.before).enumerated()), id: \.element.id) { index, row in
                    let isYou = row.id == "Vous"
                    HStack {
                        Text("\(index + 1)").font(.subheadline.monospacedDigit().weight(.bold)).frame(width: 18)
                        Text(row.id).font(.subheadline.weight(isYou ? .bold : .regular))
                        if isYou && improved {
                            Text("Record perso")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Spacer()
                        Text(row.time).font(.subheadline.monospacedDigit())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isYou ? Theme.accent.opacity(0.14) : Color(.secondarySystemBackground))
                    )
                }
            }
            Spacer(minLength: 0)
            Label("Médaille d'argent", systemImage: "medal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(improved ? Color.gray : .clear)
        }
        .padding(16)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.spring(duration: 0.6, bounce: 0.3)) { improved = true }
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(.easeInOut(duration: 0.4)) { improved = false }
            }
        }
    }
}
