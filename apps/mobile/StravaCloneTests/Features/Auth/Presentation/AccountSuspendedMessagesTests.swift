import Foundation
import Testing
@testable import StravaClone

/// « Compte suspendu »'s status line (ADR-038 §6): the end date in the athlete's time zone, or
/// « définitivement ».
struct AccountSuspendedMessagesTests {
    @Test func aTemporaryBanNamesItsEnd() {
        let suspension = AccountSuspension(
            until: Date(timeIntervalSince1970: 1_794_403_800), reason: nil, contactEmail: nil
        )
        let status = AccountSuspendedMessages.status(suspension, timeZone: TimeZone(identifier: "Europe/Paris")!)
        #expect(status == "Votre compte est suspendu jusqu'au 11 novembre 2026 à 14:30.")
    }

    @Test func aPermanentBanSaysDefinitivement() {
        let suspension = AccountSuspension(until: nil, reason: "Spam", contactEmail: nil)
        #expect(AccountSuspendedMessages.status(suspension) == "Votre compte est suspendu définitivement.")
    }
}
