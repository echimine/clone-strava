import SwiftUI

/// A Waypoint on the editor map: green start, red finish, accent in between. The touch
/// area is larger than the dot so it can be grabbed with a finger.
struct WaypointMarkerView: View {
    let role: ItineraryEditorStore.Marker.Role
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: diameter, height: diameter)
            .scaleEffect(isSelected ? 1.3 : 1)
            .shadow(radius: 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .animation(.snappy, value: isSelected)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private var diameter: CGFloat {
        role == .waypoint ? 14 : 18
    }

    private var color: Color {
        switch role {
        case .start: Color(red: 0.18, green: 0.8, blue: 0.44)
        case .waypoint: Theme.accent
        case .finish: Color(red: 0.91, green: 0.3, blue: 0.24)
        }
    }

    private var label: String {
        switch role {
        case .start: "Départ"
        case .waypoint: "Point de passage"
        case .finish: "Arrivée"
        }
    }
}

/// Handle in the middle of a Leg: pulling it inserts a Waypoint.
struct InsertionHandleView: View {
    var body: some View {
        Circle()
            .fill(.white.opacity(0.9))
            .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
            .frame(width: 12, height: 12)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .accessibilityLabel("Insérer un point de passage")
    }
}

/// Bubble above a tapped Waypoint.
struct WaypointBubble: View {
    let onRemove: () -> Void

    var body: some View {
        Button(role: .destructive, action: onRemove) {
            Label("Supprimer", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 2)
        .accessibilityIdentifier("removeWaypoint")
    }
}

/// Bubble on a tapped Leg: follow roads and trails, or a straight line.
struct LegModeBubble: View {
    let mode: LegMode
    let onSelect: (LegMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            option(.follow, title: "Suivre les chemins", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            Divider().frame(height: 24)
            option(.straight, title: "Ligne droite", symbol: "line.diagonal")
        }
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 2)
    }

    private func option(_ option: LegMode, title: String, symbol: String) -> some View {
        Button {
            onSelect(option)
        } label: {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(mode == option ? .bold : .regular))
                .foregroundStyle(mode == option ? Theme.accent : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .accessibilityAddTraits(mode == option ? .isSelected : [])
        .accessibilityIdentifier("legMode.\(option.rawValue)")
    }
}
