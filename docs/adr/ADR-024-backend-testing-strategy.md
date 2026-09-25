# ADR-024: Backend testing strategy — Vitest tiers and a CI test gate

- **Status**: accepted
- **Date**: 2026-09-25
- **Deciders**: echimine
- **Tags**: testing, vitest, ci, backend

## Context

ADR-009 and ADR-011 each mention testing only in passing ("to be wired and tested", "idempotency to test"), without deciding a runner, a fixture strategy, or what "tested" means for a given kind of code. ADR-021 §4/§6 comes closest, with two terse rules — "the bridge is tested alone (event in → expected publish out)" and "`domain/` is pure: unit-testable without a database" — but these are module-boundary rules stated in passing, not a testing strategy.

In practice, a consistent two-tier convention already exists across `apps/*` and `packages/*` (Vitest everywhere, `packages/*.test.ts` pure/mocked, `apps/*.spec.ts` split between pure-unit and real-infra integration), most recently and most deliberately demonstrated by the Better Auth + Resend work (ADR-022/023): `apps/api/src/auth/test-auth-app.ts` boots a real NestJS app against the real `docker-compose.dev.yml` Postgres/Redis, mocking only the one genuine third-party network call (Resend). Nobody wrote this convention down; new contributors (human or agent) have no ADR to check before choosing a pattern, and there is no CI gate enforcing any of it — `deploy.yml` builds and deploys the four backend images without ever running `pnpm test`.

This ADR formalizes the tiers already in use, closes the two concrete gaps found while auditing them (`apps/worker` has zero tests; no CI runs any test), and decides how CI provisions the infrastructure the integration tier needs. It covers `apps/api`, `apps/worker`, `apps/realtime`, and `packages/core`, `packages/db`, `packages/contracts`, `packages/realtime`. It does not cover `apps/admin` (a separate Next.js/jsdom profile, out of scope here) or mobile (ADR-025).

## Decision

### 1. Runner: Vitest, already the case, made explicit

Vitest (`5.0.1`) is the runner for every backend app and package, driven by `turbo run test` (`package.json`'s `"test": "turbo run test"`, `turbo.json`'s `"test"` task depending on `^build`). `apps/api`, `apps/worker`, and `apps/realtime` share one identical `vitest.config.ts` (the NestJS + SWC recipe):

```ts
import swc from "unplugin-swc";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: { globals: true, environment: "node", root: "./", include: ["src/**/*.spec.ts"] },
  plugins: [swc.vite({ module: { type: "es6" } })],
});
```

No new app introduces a different runner or config shape without a reason documented in its own ADR.

### 2. Two tiers, by directory: `packages/*.test.ts` pure, `apps/*.spec.ts` mixed

**`packages/*` — pure unit tests only, named `*.test.ts`.** No live Postgres, no live Redis, ever. This formalizes ADR-021 §6 ("`domain/` is pure") as a testing rule, not just a module-boundary rule. Two acceptable shapes, both already in the codebase:
- Pure functions/domain logic, no collaborators to fake: `packages/core/src/activities/domain/compute-metrics.test.ts`, `packages/core/src/subscriptions/domain/is-premium.test.ts`, `packages/contracts/src/common/error.test.ts`, `packages/db/src/schema/schema.test.ts` (introspects Drizzle schema objects in-process, no connection).
- A collaborator faked at its interface, per ADR-021 §4's "bridge tested alone" rule: `packages/core/src/realtime/listeners/realtime-bridge.listener.test.ts` uses a `vi.fn()`-based fake `RealtimePublisher`, never a real Redis-backed one.

**`apps/*` — `*.spec.ts`, split into two tiers by what the test needs to be true:**
- **Focused unit**: construct the class/function directly, no Nest `TestingModule`, no HTTP boot; mock only the one collaborator not under test, keep everything else real or pure. Reference: `apps/api/src/webhooks/resend.controller.spec.ts` (`new ResendWebhookController(realNotificationsService, mockedAuthService)` — real Svix signature verification, mocked `AuthService`) and `apps/realtime/src/gateway/{message-handling,token-verifier}.spec.ts` (pure functions, real `jsonwebtoken`, no network).
- **Integration**: boot a real Nest app against the real `docker-compose.dev.yml` Postgres + Redis (`pnpm db:up`); mock only genuine third-party network calls (Resend, RevenueCat, PostHog), never the app's own infrastructure. Reference implementation: `apps/api/src/auth/test-auth-app.ts` — `bootstrapTestAuthApp(options)` imports the real `CoreInfrastructureModule.forRoot`/`CoreAuthModule.forRoot`, mounts Better Auth exactly like `main.ts`, listens on a real port, and specs (`auth-flows.spec.ts`, `admin-2fa.spec.ts`) drive it over real `fetch(...)` HTTP calls. Only `NotificationsService.sendAuthEmail` is overridden to a no-op.

A new app or module follows this same decision rule: if the behavior under test is pure logic or a single collaborator's contract, write a focused unit test; if the behavior only exists as the interaction between the app and its real infrastructure (auth flows, rate limiting, DB migrations applying correctly, a BullMQ job actually running), write an integration test using a `test-<app>-app.ts` bootstrap helper shaped like `test-auth-app.ts`.

### 3. Test infrastructure: the dev Postgres/Redis, no testcontainers

Integration-tier tests run against the same `docker-compose.dev.yml` `db`/`redis` services used for local development (`TEST_DATABASE_URL`/`TEST_REDIS_URL` in `test-auth-app.ts` point at the same `127.0.0.1:5432`/`127.0.0.1:6379` ports). This is a deliberate choice, not an oversight: it keeps one set of infrastructure definitions instead of a second testcontainers/ephemeral-DB setup, at the cost of requiring `pnpm db:up` before running integration tests locally or in CI.

Two known gotchas from `test-auth-app.ts`, worth keeping as house convention rather than re-discovering per app:
- Run real Drizzle migrations once per suite (`beforeAll`) against the shared DB, never assume a pre-migrated fixture.
- Rate-limit or other Redis-keyed counters are shared across spec files/runs; clear the specific keys a suite depends on before asserting on them (`clearRateLimitCounters()`), rather than assuming a clean Redis.

### 4. Closing the two coverage gaps found

- **`apps/worker` has zero tests today** (`vitest run --passWithNoTests` is why `turbo run test` currently succeeds anyway). The next BullMQ processor added to `apps/worker` ships with at least one integration-tier test using a `test-worker-app.ts` bootstrap (same shape as `test-auth-app.ts`, adapted for a queue: enqueue a real job against real Redis, assert on its real side effects) — not retrofitted onto existing code as a separate cleanup task.
- **`apps/realtime` has unit-tier coverage only** (`message-handling.spec.ts`, `token-verifier.spec.ts` test extracted pure logic, nothing exercises the actual WebSocket gateway or Redis pub-sub wiring as a running app). The next gateway-level change ships with an integration-tier test using the same bootstrap pattern once one is written; this ADR does not require retrofitting the current gateway immediately, but the gap is now a tracked, named decision rather than an invisible one.

### 5. CI test gate

`.github/workflows/deploy.yml` currently builds and pushes four Docker images and redeploys without ever running `pnpm test` — untested code can reach the VPS today. Add a `test` job to CI (either a step in `deploy.yml` gating the build/push steps, or a separate `ci.yml` that `deploy.yml`'s job depends on — implementation detail for whoever wires this) that:
1. Provisions Postgres + Redis via GitHub Actions `services:` (matching `docker-compose.dev.yml`'s images/versions, not a different setup).
2. Runs `pnpm db:migrate` (or the equivalent CI step) against that service before tests.
3. Runs `pnpm build && pnpm test` (matching the local `npm run build` gate already required before any commit, per this project's global rule) and fails the workflow — blocking image build/push — on any test failure.

This is the same build-then-test ordering the local workflow already requires (build clean before commit); CI enforcing it too closes the gap where a passing local build with a broken test could still reach `main`/deploy today.

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| Testcontainers (ephemeral Postgres/Redis per test run) | No shared-state gotchas (rate-limit key bleed, migration ordering); closer to hermetic tests | A second infrastructure definition to maintain alongside `docker-compose.dev.yml`; slower cold start; the existing `test-auth-app.ts` pattern already works and would need a rewrite | Rejected |
| Jest instead of Vitest | More ecosystem familiarity | Already fully replaced by Vitest across every backend app; no reason to reintroduce a second runner | Rejected |
| One flat `*.spec.ts`/`*.test.ts` convention, no tier distinction | Simpler rule to state | Already diverges in practice (`packages/*` never touches real infra, `apps/*` sometimes does); pretending there's one tier would misdescribe the codebase, not simplify it | Rejected |
| Leave the CI gap open, keep testing manual/local-only | No CI setup work now | Untested code already reaches deploy today; directly contradicts the project's own "build must pass before commit" rule by not extending it to the pipeline that actually ships | Rejected |
| Retrofit full integration coverage onto `worker`/`realtime` immediately as part of this ADR | Closes both gaps today | Turns an architecture decision into an unbounded implementation task; better scoped as "the next change to these apps must include it" | Rejected |

## Consequences

### Positive
- The convention every recent test file already follows (`test-auth-app.ts` and friends) is now a documented decision, not tribal knowledge a new contributor or agent has to reverse-engineer from `git log`.
- `packages/*` stays fast and hermetic by rule, not by accident — a future PR adding a live DB call inside a `packages/core/src/**/domain/*.test.ts` file is now a violation of a written decision, not just "unusual."
- Untested code reaching `main`/deploy becomes a CI failure instead of a silent gap, closing a real production-risk hole that existed through the entire Better Auth/Resend rollout (ADR-022/023 shipped before this ADR, without a CI test gate).

### Negative / Risks
- **CI provisioning Postgres/Redis adds workflow complexity and runtime** to every push — a `services:` block, a migration step, and however long the current suite takes (currently well under a minute, but that will grow as `worker`/`realtime` gain integration tests).
- **Shared dev-DB-shaped test infrastructure means integration tests are not hermetic** across parallel CI runs if concurrency is ever added — `docker-compose.dev.yml`-shaped `services:` in a single job avoids this for now, but running specs in parallel jobs against the same DB later would need the testcontainers alternative revisited.
- **No coverage threshold is set.** This ADR decides tiers and closes two named gaps, but does not mandate a minimum coverage percentage — a future change could add tests only where convenient and still technically satisfy "the next change ships with a test" without meaningfully raising coverage. Left as a deliberate scope boundary, not an oversight: coverage percentages are a separate, disputable decision this ADR avoids forcing.

## References
- [Vitest documentation](https://vitest.dev)
- [NestJS + SWC + Vitest recipe](https://docs.nestjs.com/recipes/swc#jest) (the pattern every backend `vitest.config.ts` follows)
- [ADR-009: Backend `api` app](ADR-009-backend-api.md) (mentions testing only informally — formalized here)
- [ADR-011: Backend `worker` app](ADR-011-backend-worker.md) (idempotency-to-test principle — formalized here)
- [ADR-018: Dockerization and VPS deployment](ADR-018-docker-vps-deployment.md) (`deploy.yml`, the CI workflow this ADR adds a test gate to)
- [ADR-021: Bounded contexts and module boundaries](ADR-021-bounded-contexts-and-module-boundaries.md) (§4/§6 — the pure-domain and bridge-tested-alone rules this ADR formalizes as a testing tier)
- [ADR-022: Authentication — Better Auth](ADR-022-authentication-better-auth.md) / [ADR-023: Transactional email with Resend](ADR-023-transactional-email-resend.md) (the work whose tests — `test-auth-app.ts`, `auth-flows.spec.ts`, `admin-2fa.spec.ts`, `resend.controller.spec.ts` — are this ADR's reference implementation)

## Links
- **Depends on**: [ADR-005](ADR-005-monorepo.md), [ADR-009](ADR-009-backend-api.md), [ADR-011](ADR-011-backend-worker.md)
- **Amends**: [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md) (formalizes §4/§6's testing-adjacent rules into an explicit tier), [ADR-018](ADR-018-docker-vps-deployment.md) (adds a test gate to `deploy.yml`)
- **Related**: [ADR-022](ADR-022-authentication-better-auth.md), [ADR-023](ADR-023-transactional-email-resend.md), [ADR-025](ADR-025-mobile-testing-strategy.md) (the equivalent decision for `apps/mobile`)
