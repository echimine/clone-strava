import SwiftUI

/// The copy of « Compte suspendu » (ADR-038 §6).
enum AccountSuspendedMessages {
    static let title = "Compte suspendu"

    /// « Votre compte est suspendu jusqu'au 11 novembre 2026 à 14:30. » or « … définitivement. »
    static func status(_ suspension: AccountSuspension, timeZone: TimeZone = .current) -> String {
        guard let until = suspension.until else {
            return "Votre compte est suspendu définitivement."
        }
        var date = Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "fr_FR"))
        date.timeZone = timeZone
        var time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "fr_FR"))
        time.timeZone = timeZone
        return "Votre compte est suspendu jusqu'au \(until.formatted(date)) à \(until.formatted(time))."
    }

    static let reasonTitle = "Motif"
    static let contactIntro = "Pour contester cette décision, écrivez-nous :"
    static let noContact = "Pour contester cette décision, répondez à l'e-mail qui vous l'a annoncée."
    static let close = "OK"
}

/// « Compte suspendu » (ADR-038 §6): shown when a banned athlete tries to sign in, by Sign-in code
/// or Google. The end date or « définitivement », the reason, and the address to contest it.
struct AccountSuspendedView: View {
    let suspension: AccountSuspension
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(AccountSuspendedMessages.title)
                .font(.system(size: 30, weight: .bold))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)
            Text(AccountSuspendedMessages.status(suspension))
                .font(.body)
                .padding(.top, 8)
                .accessibilityIdentifier("suspended.status")

            if let reason = suspension.reason, !reason.isEmpty {
                Text(AccountSuspendedMessages.reasonTitle)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 24)
                Text(reason)
                    .font(.body)
                    .padding(.top, 4)
                    .accessibilityIdentifier("suspended.reason")
            }

            Group {
                if let contact = suspension.contactEmail, let url = URL(string: "mailto:\(contact)") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AccountSuspendedMessages.contactIntro)
                        Link(contact, destination: url)
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("suspended.contact")
                    }
                } else {
                    Text(AccountSuspendedMessages.noContact)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 24)

            Spacer()

            Button(AccountSuspendedMessages.close, action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("suspended.close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 72)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
    }
}

#if DEBUG
#Preview("Temporaire") {
    AccountSuspendedView(
        suspension: AccountSuspension(
            until: Date(timeIntervalSinceNow: 7 * 86_400), reason: "Propos haineux", contactEmail: "contact@nervo.app"
        ),
        onClose: {}
    )
}

#Preview("Définitif") {
    AccountSuspendedView(suspension: AccountSuspension(until: nil, reason: nil, contactEmail: nil), onClose: {})
}
#endif
