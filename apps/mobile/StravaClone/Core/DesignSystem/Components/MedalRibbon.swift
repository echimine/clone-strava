import SwiftUI

/// A personal Medal (ADR-039 §8): 1st, 2nd or 3rd fastest of the athlete at the date.
enum Medal: String, Sendable {
    case gold, silver, bronze
}

/// The ribbon medal « PR » / « 2 » / « 3 », the same drawing everywhere (ADR-039 §15).
/// Minimal version from spec #251; spec #252 owns the drawing.
struct MedalRibbon: View {
    let medal: Medal
    let size: CGFloat

    init(_ medal: Medal, size: CGFloat = 20) {
        self.medal = medal
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: size * 0.08) {
                Rectangle().fill(ribbon).frame(width: size * 0.22, height: size * 0.5).rotationEffect(.degrees(12))
                Rectangle().fill(ribbon).frame(width: size * 0.22, height: size * 0.5).rotationEffect(.degrees(-12))
            }
            Circle()
                .fill(color.gradient)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: size * 0.06))
                .overlay(
                    Text(label)
                        .font(.system(size: size * (medal == .gold ? 0.36 : 0.46), weight: .heavy))
                        .foregroundStyle(.white)
                )
                .frame(width: size * 0.8, height: size * 0.8)
                .offset(y: size * 0.22)
        }
        .frame(width: size, height: size * 1.05, alignment: .top)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var label: String {
        switch medal {
        case .gold: "PR"
        case .silver: "2"
        case .bronze: "3"
        }
    }

    private var color: Color {
        switch medal {
        case .gold: Color(red: 0.93, green: 0.70, blue: 0.13)
        case .silver: Color(white: 0.62)
        case .bronze: Color(red: 0.76, green: 0.48, blue: 0.25)
        }
    }

    private var ribbon: Color { Theme.accent.opacity(0.85) }

    private var accessibilityText: String {
        switch medal {
        case .gold: "Record personnel"
        case .silver: "2e meilleur temps"
        case .bronze: "3e meilleur temps"
        }
    }
}
