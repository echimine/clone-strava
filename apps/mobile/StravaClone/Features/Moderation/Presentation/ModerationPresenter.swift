import SwiftUI

extension View {
    /// Installed once by the app shell over the tabs (ADR-007 rule 5): every screen below can
    /// "Signaler" and "Bloquer" through `\.reportContent` and `\.blockAthlete`, without knowing
    /// this feature. The Report sheet, the Block confirmation and their toasts live here.
    func moderation(_ store: ModerationStore) -> some View {
        modifier(ModerationPresenter(store: store))
    }
}

private struct ModerationPresenter: ViewModifier {
    @Bindable var store: ModerationStore

    func body(content: Content) -> some View {
        content
            .environment(\.reportContent, ReportContentAction { [store] target, onHidden in
                store.report(target, onHidden: onHidden)
            })
            .environment(\.blockAthlete, BlockAthleteAction { [store] athlete, onBlocked in
                store.requestBlock(athlete, source: .profile, onBlocked: onBlocked)
            })
            .sheet(item: $store.sheet, onDismiss: { store.closeSheet() }) { sheet in
                ReportSheet(store: store, target: sheet.target)
            }
            // The sheet asks for its own "Bloquer aussi" confirmation.
            .confirmationDialog(
                ModerationMessages.blockConfirmationTitle(store.blockRequest?.athlete.firstName ?? ""),
                isPresented: Binding(
                    get: { store.blockRequest != nil && store.sheet == nil },
                    set: { if !$0 { store.cancelBlock() } }
                ),
                titleVisibility: .visible
            ) {
                Button(ModerationMessages.block, role: .destructive) { Task { await store.confirmBlock() } }
                    .accessibilityIdentifier("blockConfirmation.block")
                Button(ModerationMessages.cancel, role: .cancel) { store.cancelBlock() }
            } message: {
                Text(ModerationMessages.blockConfirmationMessage)
            }
            .toast($store.toast)
    }
}
