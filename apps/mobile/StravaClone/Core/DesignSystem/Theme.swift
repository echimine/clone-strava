import SwiftUI

enum Theme {
    static let accent = Color(red: 0.99, green: 0.32, blue: 0.0)
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
