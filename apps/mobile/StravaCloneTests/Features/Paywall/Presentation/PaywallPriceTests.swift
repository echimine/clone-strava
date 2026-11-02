import Foundation
import Testing
@testable import StravaClone

/// The prices the Paywall writes (ADR-035 §6): what is paid after the trial stays readable
/// outside the small print (App Store 3.1.2).
struct PaywallPriceTests {
    /// French formatting puts a no-break space before "€"; compared as a plain space.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func thePriceAfterTheTrialIsSpelledOut() {
        #expect(plain(SubscriptionOffer.yearly.priceAfterTrial) == "30 jours gratuits, puis 59,99 € par an")
        #expect(plain(SubscriptionOffer.monthly.priceAfterTrial) == "30 jours gratuits, puis 9,99 € par mois")
    }

    @Test func theYearlyOfferIsAlsoGivenPerMonth() {
        #expect(plain(SubscriptionOffer.yearly.monthlyPrice) == "5,00 €")
    }

    @Test func theYearlyOfferSavesHalfOfTwelveMonths() {
        #expect(PaywallOffering.sample(layout: .b).yearlySavingsPercent == 50)
    }
}
