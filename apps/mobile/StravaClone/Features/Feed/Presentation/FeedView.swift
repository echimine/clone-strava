import SwiftUI

/// Home tab. Knows nothing of other features (ADR-007 rule 5): the app shell passes the
/// "+" action and the content shown above the feed (e.g. the import banner).
struct FeedView<TopContent: View>: View {
    var onImportActivity: () -> Void = {}
    @ViewBuilder var topContent: () -> TopContent

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Fil",
                systemImage: "list.bullet.rectangle",
                description: Text("Les activités des athlètes suivis apparaîtront ici.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 8) { topContent() }
            .homeHeader(HomeHeaderActions(onImportActivity: onImportActivity))
        }
    }
}

extension FeedView where TopContent == EmptyView {
    init(onImportActivity: @escaping () -> Void = {}) {
        self.init(onImportActivity: onImportActivity) { EmptyView() }
    }
}

#Preview {
    FeedView()
        .tint(Theme.accent)
}
