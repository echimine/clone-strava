import Foundation

/// How the Paywall writes an offer, in French whatever the phone's language (the app's texts are
/// French). RevenueCat will give localised prices; until then they are formatted here.
extension SubscriptionOffer {
    private var currency: Decimal.FormatStyle.Currency {
        .currency(code: currencyCode).locale(Locale(identifier: "fr_FR"))
    }

    /// "59,99 €".
    var formattedPrice: String { price.formatted(currency) }
    /// "5,00 €": the price brought back to one month.
    var monthlyPrice: String {
        (period == .year ? price / 12 : price).formatted(currency.precision(.fractionLength(2)))
    }
    /// "0,00 €", for "Essayer pour 0,00 €".
    var zeroPrice: String { Decimal(0).formatted(currency) }

    var title: String { period == .year ? "Annuel" : "Mensuel" }
    var perPeriod: String { period == .year ? "par an" : "par mois" }
    var shortPeriod: String { period == .year ? "an" : "mois" }

    /// "30 jours gratuits, puis 59,99 € par an": shown above the button, outside the small print
    /// (App Store guideline 3.1.2).
    var priceAfterTrial: String {
        let price = "\(formattedPrice) \(perPeriod)"
        return trialDays.map { "\($0) jours gratuits, puis \(price)" } ?? price
    }
}

extension PaywallOffering {
    /// "−50 %": the yearly offer against twelve monthly ones.
    var yearlySavingsPercent: Int? {
        guard let year = offers.first(where: { $0.period == .year }),
              let month = offers.first(where: { $0.period == .month }),
              month.price > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: year.price / (month.price * 12)).doubleValue
        return Int(((1 - ratio) * 100).rounded())
    }
}

/// The hard-coded copy shared by the three variants (ADR-035 §6).
enum PaywallCopy {
    /// The 5 Premium benefits.
    static let premiumFeatures = [
        "Classements complets",
        "Itinéraires sur mesure",
        "Analyse de vos progrès",
        "Cartes hors ligne",
        "Suivi en direct",
    ]
    /// Also in the free app (variant B's table).
    static let freeFeatures = [
        "Enregistrer vos activités",
        "Fil d'actualité, kudos et commentaires",
        "Segments et Records perso",
    ]

    /// Auto-renewal terms the App Store asks for next to the purchase button (guideline 3.1.2).
    static func renewalTerms(_ offer: SubscriptionOffer) -> String {
        let start = offer.trialDays.map { "Essai gratuit de \($0) jours, puis \(offer.formattedPrice) \(offer.perPeriod)." }
            ?? "\(offer.formattedPrice) \(offer.perPeriod)."
        return start + " Le paiement est débité sur votre compte Apple à la fin de l'essai. L'abonnement se renouvelle "
            + "automatiquement, sauf résiliation au moins 24 heures avant la fin de la période en cours, dans les "
            + "Réglages de votre compte Apple."
    }
}
