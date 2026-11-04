import StoreKit
import SwiftUI

/// « Supprimer mon compte » (ADR-038 §13), pushed from the bottom of Réglages: what will be
/// erased, the `SignOutWarning` lines, Apple's billing with « Gérer mon abonnement » (never
/// blocking), then the Sign-in code and « Supprimer définitivement ».
struct AccountDeletionView: View {
    @State var store: AccountDeletionStore
    @State private var isManagingSubscription = false
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        Form {
            Section {
                ForEach(AccountDeletionMessages.erased, id: \.self) { line in
                    Label(line, systemImage: "trash")
                }
            } header: {
                Text(AccountDeletionMessages.erasedHeader)
            } footer: {
                Text(AccountDeletionMessages.erasedFooter)
            }
            if let warning = store.signOutWarning {
                Section(AccountDeletionMessages.lostHeader) {
                    Text(warning)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("accountDeletion.signOutWarning")
                }
            }
            if store.appStoreBilled {
                Section(AccountDeletionMessages.premiumHeader) {
                    Text(AccountDeletionMessages.premiumWarning)
                    Button(AccountDeletionMessages.manageSubscription) {
                        isManagingSubscription = true
                    }
                    .accessibilityIdentifier("accountDeletion.manageSubscription")
                }
            }
            switch store.step {
            case .confirm:
                Section {
                    Button(AccountDeletionMessages.sendCode, role: .destructive) {
                        Task { await store.sendCode() }
                    }
                    .disabled(store.isWorking)
                    .accessibilityIdentifier("accountDeletion.sendCode")
                } footer: {
                    errorText
                }
            case .code:
                Section {
                    TextField(AccountDeletionMessages.codePlaceholder, text: $store.code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isCodeFocused)
                        .accessibilityIdentifier("accountDeletion.code")
                    Button(AccountDeletionMessages.resendCode) {
                        Task { await store.sendCode() }
                    }
                    .disabled(store.isWorking)
                } header: {
                    Text(AccountDeletionMessages.codeHeader)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AccountDeletionMessages.codeFooter)
                        errorText
                    }
                }
                Section {
                    Button(AccountDeletionMessages.confirm, role: .destructive) {
                        Task { await store.confirm() }
                    }
                    .disabled(!store.canConfirm)
                    .accessibilityIdentifier("accountDeletion.confirm")
                }
            }
        }
        .navigationTitle(AccountDeletionMessages.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.isWorking { ProgressView() }
        }
        .task { await store.load() }
        .onChange(of: store.step) { _, step in
            if step == .code { isCodeFocused = true }
        }
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
    }

    @ViewBuilder private var errorText: some View {
        if let error = store.error {
            Text(error)
                .foregroundStyle(.red)
                .accessibilityIdentifier("accountDeletion.error")
        }
    }
}
