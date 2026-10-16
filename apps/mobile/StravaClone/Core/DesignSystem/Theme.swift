import SwiftUI

enum Theme {
    /// Nervo orange, sRGB #FC5200 (ADR-032 §2), read from the launch screen's colour so both
    /// stay one value and the splash hands off from the launch screen without a seam (§4).
    ///
    /// iOS draws the launch screen colour's sRGB components as if they were Display P3, so
    /// `LaunchBackground` stores the Display P3 components of #FC5200 under an sRGB tag. Read
    /// back as Display P3 here, they give #FC5200 again.
    static let accent: Color = {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(named: "LaunchBackground")?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Color(.displayP3, red: red, green: green, blue: blue, opacity: alpha)
    }()
    static let spacing: CGFloat = 16
}

/// Placeholder screen for features not implemented yet.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .navigationTitle(title)
        }
    }
}
