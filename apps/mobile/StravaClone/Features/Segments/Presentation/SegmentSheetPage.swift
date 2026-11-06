import SwiftUI

/// A Segment's sheet (ADR-039 §15), one page that scrolls: map, figures, profile, « Mes
/// efforts », « Légende locale », the top 10 of Tous with my line, « Voir le classement ». The
/// toolbar holds the star and the ⋯ menu (« Signaler ce Segment »; « Renommer » and
/// « Supprimer » for its creator).
struct SegmentSheetPage: View {
    @State private var store: SegmentSheetStore
    @State private var renaming: String?
    private let makeLeaderboardStore: @MainActor (String) -> LeaderboardStore
    private let paywall: @MainActor (AnalyticsEvent.PaywallEntry, @escaping @MainActor () -> Void) -> AnyView
    @Environment(\.reportContent) private var reportContent

    init(
        request: SegmentRequest,
        makeStore: @MainActor (String, @escaping @MainActor () -> Void) -> SegmentSheetStore,
        makeLeaderboardStore: @escaping @MainActor (String) -> LeaderboardStore,
        paywall: @escaping @MainActor (AnalyticsEvent.PaywallEntry, @escaping @MainActor () -> Void) -> AnyView,
        onDeleted: @escaping @MainActor () -> Void
    ) {
        _store = State(initialValue: makeStore(request.segmentID, onDeleted))
        self.makeLeaderboardStore = makeLeaderboardStore
        self.paywall = paywall
    }

    var body: some View {
        content
            .navigationTitle(store.sheet?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toast($store.toast)
            .task { await store.load() }
            .alert(SegmentMessages.renameTitle, isPresented: isRenaming) {
                TextField(SegmentMessages.renamePlaceholder, text: Binding(get: { renaming ?? "" }, set: { renaming = $0 }))
                Button(SegmentMessages.save) {
                    let name = renaming ?? ""
                    Task { await store.rename(to: name) }
                }
                .disabled(!SegmentMessages.isValidName(renaming ?? ""))
                Button(SegmentMessages.cancel, role: .cancel) {}
            } message: {
                Text(SegmentMessages.renameFooter)
            }
            .alert(SegmentMessages.deleteTitle, isPresented: isDeletion(.confirming)) {
                Button(SegmentMessages.delete, role: .destructive) { Task { await store.confirmDelete() } }
                Button(SegmentMessages.cancel, role: .cancel) {}
            } message: {
                Text(SegmentMessages.deleteMessage)
            }
            .alert(SegmentMessages.deleteRefusedTitle, isPresented: isDeletion(.refused)) {
                Button(SegmentMessages.ok, role: .cancel) {}
            } message: {
                Text(SegmentMessages.deleteRefusedMessage)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .gone:
            ContentUnavailableView(SegmentMessages.gone, systemImage: "mappin.slash", description: Text(SegmentMessages.goneDetail))
                .accessibilityIdentifier("segmentSheet.gone")
        case .failed(let message):
            ContentUnavailableView {
                Label(SegmentMessages.loadFailed, systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button(SegmentMessages.retry) { Task { await store.load() } }
            }
        case .loaded(let sheet):
            ScrollView {
                SegmentSheetContent(sheet: sheet) {
                    LeaderboardPage(segmentName: sheet.name, makeStore: { makeLeaderboardStore(sheet.id) }, paywall: paywall)
                }
            }
            .refreshable { await store.load() }
            .accessibilityIdentifier("segmentSheet")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let sheet = store.sheet {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await store.toggleFavorite() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: sheet.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(sheet.isFavorite ? Color.yellow : Color.primary)
                        Text(sheet.favoriteCount.formatted(.number.locale(ActivityFormatters.locale)))
                            .font(.footnote)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel(sheet.isFavorite ? SegmentMessages.removeFavorite : SegmentMessages.addFavorite)
                .accessibilityValue("\(sheet.favoriteCount)")
                .accessibilityIdentifier("segmentSheet.star")
                Menu {
                    if sheet.isMine {
                        Button(SegmentMessages.rename, systemImage: "pencil") { renaming = sheet.name }
                        Button(SegmentMessages.delete, systemImage: "trash", role: .destructive) { store.requestDelete() }
                    }
                    Button(SegmentMessages.report, systemImage: "flag") {
                        reportContent?(.segment(sheet.id))
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("Plus d'options")
                }
                .accessibilityIdentifier("segmentSheet.menu")
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func isDeletion(_ deletion: SegmentSheetStore.Deletion) -> Binding<Bool> {
        Binding(get: { store.deletion == deletion }, set: { if !$0 { store.deletion = nil } })
    }
}
