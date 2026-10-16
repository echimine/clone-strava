import SwiftUI

enum Theme {
    /// Nervo orange, sRGB #FC5200 (ADR-032 §2), read from the launch screen's colour so both
    /// stay one value and the splash hands off from the launch screen without a seam (§4).
    ///
    /// Do not "fix" the colour set nor this conversion: iOS resolves the launch screen colour to
    /// sRGB components and draws them as Display P3, whatever space the set declares (sRGB
    /// #FC5200, or the same colour declared in display-p3, both showed as (255,61,0) = #FF3D00
    /// on the iOS 27 simulator). So `LaunchBackground` stores the Display P3 components of
    /// #FC5200 under an sRGB tag, and reading them back as Display P3 here gives #FC5200 again.
    /// Measured: launch screen (252,82,2), splash (252,82,0), the 2 being the system's 8-bit
    /// rounding. Details in `project.yml` (`UILaunchScreen`); checked by `ThemeTests`.
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
