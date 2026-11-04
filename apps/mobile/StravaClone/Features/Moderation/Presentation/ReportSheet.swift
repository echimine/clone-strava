import SwiftUI

/// The Report sheet (ADR-038 §9): the fixed reasons, an optional note (required with "Autre"),
/// "Envoyer"; then "Merci, notre équipe va examiner ce signalement" with "Bloquer aussi
/// <prénom>".
struct ReportSheet: View {
    @Bindable var store: ModerationStore
    let target: ReportTarget

    var body: some View {
        NavigationStack {
            Group {
                if case .done(let outcome) = store.sheetPhase {
                    confirmation(outcome)
                } else {
                    form
                }
            }
            .navigationTitle(ModerationMessages.reportTitle(target.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .toast($store.sheetToast)
        .confirmationDialog(
            ModerationMessages.blockConfirmationTitle(store.blockRequest?.athlete.firstName ?? ""),
            isPresented: Binding(
                get: { store.blockRequest != nil },
                set: { if !$0 { store.cancelBlock() } }
            ),
            titleVisibility: .visible
        ) {
            Button(ModerationMessages.block, role: .destructive) { Task { await store.confirmBlock() } }
            Button(ModerationMessages.cancel, role: .cancel) { store.cancelBlock() }
        } message: {
            Text(ModerationMessages.blockConfirmationMessage)
        }
        .interactiveDismissDisabled(store.sheetPhase == .sending)
        .accessibilityIdentifier("reportSheet")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if case .done = store.sheetPhase {
            ToolbarItem(placement: .confirmationAction) {
                Button(ModerationMessages.close) { store.closeSheet() }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button(ModerationMessages.cancel) { store.closeSheet() }
                    .disabled(store.sheetPhase == .sending)
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.sheetPhase == .sending {
                    ProgressView()
                } else {
                    Button(ModerationMessages.send) { Task { await store.send() } }
                        .disabled(!store.canSend)
                        .accessibilityIdentifier("reportSheet.send")
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section(ModerationMessages.reasonHeader) {
                ForEach(store.reasons, id: \.self) { reason in
                    Button {
                        store.reason = reason
                    } label: {
                        HStack {
                            Text(ModerationMessages.reason(reason))
                                .foregroundStyle(.primary)
                            Spacer()
                            if store.reason == reason {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .accessibilityAddTraits(store.reason == reason ? .isSelected : [])
                    .accessibilityIdentifier("reportSheet.reason.\(reason.rawValue)")
                }
            }
            Section {
                TextField(
                    store.reason == .other ? ModerationMessages.noteRequiredPlaceholder : ModerationMessages.notePlaceholder,
                    text: $store.note,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .accessibilityIdentifier("reportSheet.note")
            } header: {
                Text(ModerationMessages.noteHeader)
            } footer: {
                Text(ModerationMessages.noteFooter(store.reason))
            }
        }
        .disabled(store.sheetPhase == .sending)
    }

    private func confirmation(_ outcome: ReportOutcome) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            VStack(spacing: 8) {
                Text(outcome == .reported ? ModerationMessages.thanks : ModerationMessages.alreadyReported)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if outcome == .alreadyReported {
                    Text(ModerationMessages.alreadyReportedDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Button(ModerationMessages.blockToo(target.author.firstName), role: .destructive) {
                store.blockReportedAuthor()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reportSheet.blockToo")
        }
        .padding(Theme.spacing * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("reportSheet.done")
    }
}
