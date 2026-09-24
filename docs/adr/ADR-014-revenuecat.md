# ADR-014: Subscriptions with RevenueCat

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: subscriptions, ios, monetization, revenuecat

## Context

The app offers a **premium subscription** (advanced features, to be defined), sold as an in-app purchase on iOS. We need to:
- sell and renew subscriptions via the App Store (StoreKit);
- know, **in the app and in the API**, whether a user is premium;
- display a **paywall with the app's own design**;
- be able to **test prices, trial lengths and paywall variants** without shipping a new version.

Handling StoreKit directly means validating receipts, tracking renewals, refunds and grace periods, and computing revenue ourselves.

## Decision

We use **RevenueCat** for in-app purchases, with a **custom SwiftUI paywall**.

### iOS side

| Topic | Choice |
|---|---|
| SDK | **`purchases-ios`** (RevenueCat) via Swift Package Manager; no `RevenueCatUI` |
| Paywall | **Custom SwiftUI screen**, fed by RevenueCat's **current offering** (products, localized prices, trial) |
| Entitlements | A `premium` **entitlement**; the app reads `CustomerInfo` to show or hide features |
| Identity | `Purchases.logIn(userId)` after sign-in (same identifier as our database and PostHog), `logOut()` on sign-out |
| App Store requirements | "Restore purchases" button, links to the terms and the privacy policy, subscription management via iOS settings |

**Remotely controlled paywall despite the custom code:**
- **Prices, durations and trials** come from offerings: changing them does not require a new version.
- **Offering metadata** (JSON configurable in RevenueCat) drives the display variants coded in the app: title, highlighted selling point, recommended offer, layout variant (`"layout": "A"` or `"B"`).
- A paywall variant that does not yet exist in the code requires a new version.

**Architecture (ADR-007)**: the paywall is a `Features/Paywall` feature. The RevenueCat SDK stays in `Infrastructure/`, behind a domain protocol (`SubscriptionService`: offers, purchase, restore, status). Other features only know this protocol.

### Backend side

The app is not authoritative for the API: the API must know by itself whether a user is premium.

1. RevenueCat sends a **webhook** to the API: `POST /v1/webhooks/revenuecat`, authenticated by a secret header configured in RevenueCat.
2. The API checks the secret, records the event (deduplicated by its ID) and **enqueues a job** (`sync-subscription`), then responds `200` immediately.
3. The worker fetches the **full subscriber state via the RevenueCat REST API** (rather than relying on webhook ordering) and updates the user's premium status in the database.
4. The worker also sends the event to PostHog (`subscription_started`, `subscription_renewed`, `subscription_cancelled`…) to link revenue and usage (ADR-015).
5. Premium-only endpoints check this status in the database.

The table that stores the subscription status does not exist in the slide 09 model: it will be added in the data model ADR.

### Monetization A/B tests

Tests of **prices, durations, trials and paywall variants** go through **RevenueCat Experiments**: each group receives a different offering, and RevenueCat measures conversion, revenue and retention. Common rules in ADR-016.

### Prerequisites

- **Paid Apple Developer account** and "Paid Apps" agreement signed in App Store Connect: **mandatory**, including for sandbox testing. **Blocking until the account question is resolved.**
- Subscription products created in App Store Connect, In-App Purchase API key and App Store server notifications configured to RevenueCat.
- StoreKit configuration file in Xcode to test locally without App Store Connect early in development.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| StoreKit 2 alone, without RevenueCat | Validation, renewals, refunds, webhooks and revenue statistics to build ourselves; no price A/B testing |
| RevenueCat Paywalls (`RevenueCatUI`) | Less design freedom; offering metadata already provides part of the remote control |
| Adapty, Qonversion, Superwall | Functionally similar; RevenueCat is the most widespread and best documented |
| Premium status read only in the app | The API cannot protect premium features server-side |
| Webhook handled directly in the API (without a worker) | Call to RevenueCat while responding to the webhook; in case of an outage, dependence on RevenueCat's limited number of retries |
| Apply the webhook content without re-reading the full state | Webhooks may arrive out of order, duplicated or lost: risk of a wrong status |
| `POST /v1/subscriptions/sync` endpoint called by the app after a purchase | Would reduce the delay before the API sees premium, but the webhook is enough for the MVP; can be added later if the delay is a problem |

## Consequences

### Positive
- Purchases, renewals and refunds handled without Apple-specific server code.
- Prices and offers can be changed and tested without a new version.
- Paywall with the app's design.
- Premium status known to the API, so premium features are protected server-side.

### Negative / Risks
- **Apple Developer account required** before any real implementation.
- **Cost**: RevenueCat is free up to a certain tracked monthly revenue, then takes a percentage. Check the current pricing.
- **Dependency** on a third-party service for subscription state (the App Store remains the true source).
- **Custom paywall**: each new layout variant requires an app release.
- **Accepted delay**: between the purchase and the webhook's arrival (usually a few seconds), the API may not yet see the user as premium. The app relies on `CustomerInfo` for immediate display. We wait for the webhook, with no app-triggered sync.

## References
- RevenueCat iOS: https://www.revenuecat.com/docs/getting-started/installation/ios
- Offerings and metadata: https://www.revenuecat.com/docs/tools/offering-metadata
- Webhooks: https://www.revenuecat.com/docs/integrations/webhooks
- Experiments: https://www.revenuecat.com/docs/tools/experiments-v1
- [ADR-015: Analytics and feature flags with PostHog](ADR-015-posthog.md)
- [ADR-016: Experimentation strategy](ADR-016-experimentation.md)

## Links

- **Related**: [ADR-006](ADR-006-mobile-stack.md), [ADR-007](ADR-007-mobile-architecture.md), [ADR-009](ADR-009-backend-api.md), [ADR-011](ADR-011-backend-worker.md), [ADR-015](ADR-015-posthog.md), [ADR-016](ADR-016-experimentation.md)
