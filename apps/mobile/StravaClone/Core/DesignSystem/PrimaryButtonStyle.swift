import SwiftUI

/// The main button of the getting-started screens (Welcome, account screen, Sign-in code):
/// a full-width Nervo orange capsule, paler while disabled.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(Theme.accent.opacity(isEnabled ? 1 : 0.3)))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}
