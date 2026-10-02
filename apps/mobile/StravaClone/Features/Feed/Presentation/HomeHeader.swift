import SwiftUI

/// Actions of the home header. Each button only reports the tap; the screens behind
/// them (import, search, subscription, messages, notifications) are wired separately.
struct HomeHeaderActions {
    /// "+" → "Importer une activité".
    var onImportActivity: () -> Void = {}
    var onSearch: () -> Void = {}
    var onSubscribe: () -> Void = {}
    var onMessages: () -> Void = {}
    var onNotifications: () -> Void = {}
}

extension View {
    /// Home header in the navigation bar: "+" and search on the left, "S'abonner" in the
    /// middle, messages and notifications on the right. Native toolbar items, so they get
    /// Liquid Glass on iOS 26; standard bar buttons on earlier versions (iOS 17 minimum, ADR-007).
    func homeHeader(_ actions: HomeHeaderActions) -> some View {
        modifier(HomeHeaderModifier(actions: actions))
    }
}

private struct HomeHeaderModifier: ViewModifier {
    let actions: HomeHeaderActions

    func body(content: Content) -> some View {
        headerToolbar(content)
            // Header buttons are black (white in dark mode), not the app accent.
            .tint(.primary)
    }

    @ViewBuilder
    private func headerToolbar(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { glassToolbar }
        } else {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { legacyToolbar }
        }
    }

    /// iOS 26: every button gets its own glass circle (`ToolbarSpacer` between them).
    /// The principal slot gets no shared glass background, so "S'abonner" draws its own
    /// glass capsule with `glassEffect`.
    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var glassToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { addButton }
        ToolbarSpacer(.fixed, placement: .topBarLeading)
        ToolbarItem(placement: .topBarLeading) { searchButton }

        ToolbarItem(placement: .principal) {
            subscribeButton
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) { messagesButton }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) { notificationsButton }
    }

    @ToolbarContentBuilder
    private var legacyToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            addButton
            searchButton
        }
        ToolbarItem(placement: .principal) {
            subscribeButton.buttonStyle(.bordered)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            messagesButton
            notificationsButton
        }
    }

    /// "+" opens a menu, the entry point for every way of adding an activity.
    private var addButton: some View {
        Menu {
            Button(action: actions.onImportActivity) {
                Label("Importer une activité", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("homeHeader.importActivity")
        } label: {
            Label("Ajouter", systemImage: "plus")
        }
        .accessibilityIdentifier("homeHeader.add")
    }

    private var searchButton: some View {
        Button(action: actions.onSearch) {
            Label("Rechercher", systemImage: "magnifyingglass")
        }
        .accessibilityIdentifier("homeHeader.search")
    }

    private var subscribeButton: some View {
        Button(action: actions.onSubscribe) {
            Text("S'abonner")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityIdentifier("homeHeader.subscribe")
    }

    private var messagesButton: some View {
        Button(action: actions.onMessages) {
            Label("Messages", systemImage: "bubble.left.and.bubble.right")
        }
        .accessibilityIdentifier("homeHeader.messages")
    }

    private var notificationsButton: some View {
        Button(action: actions.onNotifications) {
            Label("Notifications", systemImage: "bell")
        }
        .accessibilityIdentifier("homeHeader.notifications")
    }
}
