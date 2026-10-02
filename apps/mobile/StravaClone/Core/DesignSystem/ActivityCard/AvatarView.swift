import SwiftUI

/// Round user picture, falling back to initials on the accent color.
struct AvatarView: View {
    let name: String
    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        RemoteImage(url: url) {
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.accent.gradient)
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
