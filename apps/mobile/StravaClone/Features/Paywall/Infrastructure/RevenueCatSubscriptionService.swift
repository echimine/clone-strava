import Foundation
import RevenueCat

/// `SubscriptionService` over RevenueCat (ADR-014). Only this file imports the SDK.
///
/// Wired to RevenueCat's **Test Store** for now (a `test_` key, no Apple Developer account
/// needed): a purchase opens RevenueCat's test dialog (valid purchase, failed purchase, cancel),
/// grants the `premium` entitlement and reaches the dashboard's Sandbox view. The app is never
/// published, so Release builds may use the Test Store key too (the SDK crashes otherwise).
///
/// The Paywall's offering is RevenueCat's current offering **for this user**: an Experiment
/// (ADR-016) serves each group its own offering, whose `layout` metadata picks the variant.
final class RevenueCatSubscriptionService: SubscriptionService, SubscriberIdentity, PremiumStatus, @unchecked Sendable {
    /// The entitlement Premium features check (ADR-014).
    static let premiumEntitlement = "premium"

    private let purchases: Purchases
    private let lock = NSLock()
    /// The packages of the last offering shown, by product id, to buy the picked offer.
    private var packages: [String: Package] = [:]
    /// The last `logIn` / `logOut`: offerings wait for it, so an Experiment enrolls our user id,
    /// not the anonymous one.
    private var identityChange: Task<Void, Never>?

    private init(purchases: Purchases) {
        self.purchases = purchases
    }

    /// A configured service, or `nil` without an API key (local builds without
    /// `Secrets.xcconfig`, tests): the app then keeps the unwired adapter.
    static func make(apiKey: String) -> RevenueCatSubscriptionService? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        let configuration = RevenueCat.Configuration.Builder(withAPIKey: key)
            .with(dangerousSettings: DangerousSettings(
                autoSyncPurchases: true,
                // Never published (no App Store build): Release builds installed on a phone keep
                // the Test Store.
                forceAllowTestStoreInReleaseBuilds: key.hasPrefix("test_")
            ))
            .build()
        return RevenueCatSubscriptionService(purchases: Purchases.configure(with: configuration))
    }

    // MARK: SubscriberIdentity

    func logIn(userId: String) {
        changeIdentity { purchases in
            if purchases.appUserID != userId {
                _ = try? await purchases.logIn(userId)
            }
        }
    }

    func logOut() {
        changeIdentity { purchases in
            if !purchases.isAnonymous {
                _ = try? await purchases.logOut()
            }
        }
    }

    private func changeIdentity(_ change: @escaping @Sendable (Purchases) async -> Void) {
        let purchases = purchases
        lock.withLock {
            let previous = identityChange
            identityChange = Task {
                await previous?.value
                await change(purchases)
            }
        }
    }

    // MARK: PremiumStatus

    /// The SDK's `customerInfoStream`: the cached customer at once, then each change (a
    /// purchase, an expiry, a `logIn` to another subscriber).
    func premiumUpdates() -> AsyncStream<Bool> {
        let purchases = purchases
        return AsyncStream { continuation in
            let task = Task {
                for await customerInfo in purchases.customerInfoStream {
                    continuation.yield(Self.isPremium(customerInfo))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: SubscriptionService

    func paywallOffering() async throws -> PaywallOffering {
        await lock.withLock { identityChange }?.value
        guard let current = try await purchases.offerings().current else {
            throw RevenueCatOfferingMapping.NoSubscription()
        }
        let offering = try RevenueCatOfferingMapping.offering(from: Self.snapshot(of: current))
        let packages = Dictionary(
            current.availablePackages.map { ($0.storeProduct.productIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        lock.withLock { self.packages = packages }
        return offering
    }

    func startTrial(_ offer: SubscriptionOffer) async -> PurchaseOutcome {
        guard let package = lock.withLock({ packages[offer.id] }) else { return .failed }
        do {
            let result = try await purchases.purchase(package: package)
            if result.userCancelled { return .cancelled }
            return Self.isPremium(result.customerInfo) ? .subscribed : .failed
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        } catch {
            return .failed
        }
    }

    func restorePurchases() async -> RestoreOutcome {
        do {
            let customerInfo = try await purchases.restorePurchases()
            return Self.isPremium(customerInfo) ? .restored : .nothingToRestore
        } catch {
            return .failed
        }
    }

    // MARK: Mapping

    private static func isPremium(_ customerInfo: CustomerInfo) -> Bool {
        customerInfo.entitlements[premiumEntitlement]?.isActive == true
    }

    private static func snapshot(of offering: Offering) -> RevenueCatOfferingSnapshot {
        RevenueCatOfferingSnapshot(
            products: offering.availablePackages.map { package in
                let product = package.storeProduct
                let trial = product.introductoryDiscount.flatMap { discount in
                    discount.paymentMode == .freeTrial ? discount.subscriptionPeriod : nil
                }
                return RevenueCatOfferingSnapshot.Product(
                    id: product.productIdentifier,
                    price: product.price,
                    currencyCode: product.currencyCode,
                    period: product.subscriptionPeriod.map(period),
                    freeTrial: trial.map(period)
                )
            },
            metadata: offering.metadata.compactMapValues { $0 as? String }
        )
    }

    private static func period(_ period: SubscriptionPeriod) -> (value: Int, unit: RevenueCatOfferingSnapshot.Product.Unit) {
        let unit: RevenueCatOfferingSnapshot.Product.Unit
        switch period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: unit = .day
        }
        return (period.value, unit)
    }
}
