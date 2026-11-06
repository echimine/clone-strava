import SwiftUI

/// Ribbon medal as on Strava (ADR-039 §15): « PR » on gold, « 2 » on silver, « 3 » on bronze.
/// The same drawing everywhere: « Résultats », the map of the Activity, the card's
/// « Performances » and the Segment sheet.
struct MedalRibbon: View {
    private let medal: Medal
    private let size: CGFloat

    init(_ medal: Medal, size: CGFloat = 20) {
        self.medal = medal
        self.size = size
    }

    var body: some View {
        let colors = Self.colors(medal)
        ZStack(alignment: .top) {
            RibbonShape()
                .fill(colors.dark)
                .frame(width: size * 0.62, height: size * 0.42)
            Circle()
                .fill(LinearGradient(colors: [colors.light, colors.dark], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: max(1, size * 0.06)).padding(size * 0.07))
                .overlay(
                    Text(Self.mark(medal))
                        .font(.system(size: size * (medal == .gold ? 0.26 : 0.32), weight: .heavy))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                )
                .frame(width: size * 0.74, height: size * 0.74)
                .padding(.top, size * 0.28)
        }
        .frame(width: size, height: size * 1.02)
        .accessibilityElement()
        .accessibilityLabel(Self.accessibilityLabel(medal))
    }

    static func mark(_ medal: Medal) -> String {
        switch medal {
        case .gold: "PR"
        case .silver: "2"
        case .bronze: "3"
        }
    }

    static func accessibilityLabel(_ medal: Medal) -> String {
        switch medal {
        case .gold: "Médaille d'or"
        case .silver: "Médaille d'argent"
        case .bronze: "Médaille de bronze"
        }
    }

    /// Light at the top, dark at the bottom.
    private static func colors(_ medal: Medal) -> (light: Color, dark: Color) {
        switch medal {
        case .gold: (Color(red: 0.98, green: 0.80, blue: 0.30), Color(red: 0.86, green: 0.62, blue: 0.08))
        case .silver: (Color(red: 0.70, green: 0.72, blue: 0.75), Color(red: 0.50, green: 0.52, blue: 0.56))
        case .bronze: (Color(red: 0.80, green: 0.52, blue: 0.33), Color(red: 0.62, green: 0.36, blue: 0.20))
        }
    }
}

/// The ribbon above the medal: a trapezoid open in a V at the bottom.
private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(Medal.allCases, id: \.self) { MedalRibbon($0, size: 40) }
    }
    .padding()
}
