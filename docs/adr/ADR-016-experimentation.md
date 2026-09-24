# ADR-016: Experimentation strategy (A/B tests)

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: experimentation, ab-testing, feature-flags

## Context

We want to verify through measurement whether a change is better than what exists: a price, a paywall, but also an onboarding screen, the placement of a button, the content of an activity summary. Two tools can run A/B tests: **RevenueCat Experiments** and **PostHog Experiments**. Without rules, we risk testing the same thing in both tools, skewing the results, or piling up dead flags in the code.

## Decision

### Who tests what

| What we test | Tool | Measured by |
|---|---|---|
| **Monetization**: price, duration, free trial, recommended offer, paywall variant | **RevenueCat Experiments** (one offering per group, display variants via metadata, ADR-014) | Conversion, revenue, subscriber retention |
| **Product**: onboarding, screens, flows, copy, features | **PostHog Experiments** (multivariate flag, ADR-015) | PostHog events (activation, retention, usage) |

**Rule**: everything related to the paywall and prices goes **only** through RevenueCat. PostHog never drives the paywall, to prevent two experiments from overlapping on the same screen.

### Experiment lifecycle

1. **Written hypothesis**: "If we show the map in the activity summary, more users will record a second activity within the week."
2. A single **primary metric** (e.g. `second_activity_recorded` within 7 days) and **guardrail metrics** that must not degrade (e.g. crash rate, uninstalls, premium conversion).
3. **Sample size and duration** calculated before launch (the tool's calculator). Minimum duration of one full week, to cover weekday and weekend habits.
4. **Launch**: random assignment, most often 50/50.
5. **No early stopping** because a result "looks good": we wait for the planned sample size. Only exception: a guardrail metric that degrades clearly.
6. **Decision**: we keep the winning variant, or the control if the difference is not significant.
7. **Cleanup**: the flag and the losing variant are **removed from the code within two weeks** after the decision.

### PostHog flag naming

| Prefix | Usage | Example |
|---|---|---|
| `exp-` | A/B experiment, limited duration | `exp-onboarding-3-screens` |
| `ff-` | Progressive rollout of a feature | `ff-segments-live` |
| `kill-` | Permanent kill switch | `kill-background-upload` |

### Rules in the code

- The variant is read in the **store or the service** via the `FeatureFlags` protocol (ADR-015), never directly in the view.
- **Default value = control**: if the flag is not available, the user sees the current behavior.
- The flag is read **at the moment the user sees the tested element**: this is what records their exposure. Reading it too early would count users who never saw the variant.
- An experiment that also changes server behavior reads the flag **on the backend** with the same `userId`, so that the app and the API see the same variant.
- No more than a few simultaneous experiments, and **never two experiments on the same screen**.

### User volume

An A/B test only gives a reliable result with enough users. As long as the number of users is low:
- we favor **progressive rollouts** (`ff-`) and watching the metrics;
- we only launch an experiment if the calculated sample size is reachable within a reasonable time (a few weeks).

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Test everything in PostHog, including prices | PostHog does not know actual subscription revenue as well as RevenueCat, and does not drive App Store offers |
| Test everything in RevenueCat | RevenueCat only tests offerings and the paywall |
| No shared rules | Overlapping experiments, skewed results, flags forgotten in the code |

## Consequences

### Positive
- Each type of test has a clear tool, with no overlap.
- Decisions based on significant results rather than intuition.
- Clean code: flags have a limited lifetime and explicit naming.

### Negative / Risks
- **Discipline**: hypothesis, sample size and cleanup require rigor for every test.
- **Few users at first**: most tests will be inconclusive; we will have to accept that.
- **Consent** (ADR-015): users who decline measurement do not count in PostHog results.

## References
- PostHog Experiments: https://posthog.com/docs/experiments
- RevenueCat Experiments: https://www.revenuecat.com/docs/tools/experiments-v1
- [ADR-014: Subscriptions with RevenueCat](ADR-014-revenuecat.md)
- [ADR-015: Analytics and feature flags with PostHog](ADR-015-posthog.md)

## Links

- **Depends on**: [ADR-014](ADR-014-revenuecat.md) (RevenueCat), [ADR-015](ADR-015-posthog.md) (PostHog)
