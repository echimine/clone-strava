# ADR-026: OpenAPI → Swift type generation and contract checks in CI

- **Status**: accepted
- **Date**: 2026-09-25
- **Deciders**: echimine
- **Tags**: openapi, swift, codegen, contracts, ci, mobile

## Context

ADR-005 decided that the iOS app's network models would be **generated from an OpenAPI spec** derived from the Zod contracts (`packages/contracts`), since Zod cannot be consumed from Swift. ADR-009 made the API expose that spec (`nestjs-zod` + `@nestjs/swagger`, served at `/docs/openapi.json`), and ADR-005 kept "OpenAPI → Swift generation to set up" as an open risk.

That step never happened. The app hand-writes its DTOs (`APIClient` + `Codable` structs), so a contract change on the API — a renamed field, a new required property, a changed enum — compiles fine on both sides and fails only at runtime on a device. Nothing in CI connects the two toolchains: `deploy.yml` is backend-only, and ADR-025 §4's macOS job was recorded as "not implemented yet".

This ADR decides how the Swift types are generated and which checks keep the TypeScript contracts and the Swift code in sync.

## Decision

### 1. Tool: Apple's `swift-openapi-generator`, as a build-time SPM plugin

`apps/mobile/project.yml` adds `swift-openapi-generator` as a **build tool plugin** on the `StravaClone` target, plus `swift-openapi-runtime` and `swift-openapi-urlsession` as dependencies. At every build, the plugin reads two files under `StravaClone/Core/Network/OpenAPI/`:
- `openapi.json`: the spec, which is committed;
- `openapi-generator-config.yaml`: `generate: [types, client]`, `accessModifier: internal`.

From these it generates `Components.Schemas.*` and a typed `Client`. **Generated Swift is never committed**: it is rebuilt from the spec on every build, so it cannot drift from it.

`xcodebuild` refuses unapproved plugins, so the `mobile:test*` scripts pass `-skipPackagePluginValidation`. In Xcode the plugin is trusted once per machine.

### 2. Source of truth: a committed `openapi.json`, exported without a running server

`apps/api/src/openapi/document.ts` holds the two things the server and the export must share: `applyGlobalPrefix` (the `/v1` prefix and its exclusions) and `createOpenApiDocument`. `main.ts` uses both. `apps/api/src/openapi/export.ts` builds the app with `NestFactory.create(AppModule, { preview: true })`. Preview mode builds the module graph without instantiating providers, so there is no database or Redis connection and no migration. The export then writes the spec as stable, pretty-printed JSON, and running it twice on an unchanged API produces a byte-identical file.

```bash
pnpm mobile:sync-openapi   # turbo build --filter=api (contracts included) + export
```

The spec is committed rather than fetched at build time. Mobile builds then stay offline and reproducible, and every contract change shows up as a reviewable diff to `openapi.json` in the PR.

### 3. Three checks, one per link of the chain

| # | Link | Check | Where |
|---|---|---|---|
| 1 | Zod (TS) → `openapi.json` | re-export, then `git diff --exit-code` on the committed spec | `deploy.yml`, `test` job (ubuntu, seconds) |
| 2 | `openapi.json` → Swift | the plugin regenerates the types and the app plus tests must compile | `mobile-ci.yml` (macOS) |
| 3 | Swift types ↔ real payloads | `OpenAPIContractTests`: a realistic API payload decodes into the generated type, re-encodes with the keys the API expects, and a payload missing a required field is rejected | Swift Testing, run by #2 |

A Zod change that is not re-synced fails #1. Once re-synced, a change that breaks Swift code fails #2 or #3.

### 4. Two workflows, not one

Check #1 lives in `deploy.yml`, where it is cheap and runs next to the backend build that already has everything it needs. Check #2 lives in a new `mobile-ci.yml`, as ADR-025 §4 prescribed:
- it runs on a macOS runner with Xcode pinned via `setup-xcode`;
- it is path-filtered to `apps/mobile/**`, which includes `openapi.json` itself;
- it runs on PRs and on pushes to `main`.

The two are kept apart so that a mobile failure never blocks a backend deploy, and a backend-only change never starts a macOS runner.

This implements ADR-025 §4 for **unit tests only**. `StravaCloneUITests` needs a running backend, so it stays local (`pnpm mobile:test:ui`).

### 5. Scope: types available, `APIClient` unchanged

This ADR does not migrate existing calls. `APIClient` keeps its typed `APIError` normalization and bearer handling. New `/v1` endpoints use the generated `Components.Schemas.*` (and later the generated `Client`) instead of hand-written DTOs, and existing ones migrate when touched.

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| `openapi-generator-cli` (OpenAPITools) | Many languages, very configurable | Java toolchain, Mustache templates, Swift output that is not Swift 6 / strict-concurrency native, not an SPM plugin | Rejected |
| Generate once with the CLI, commit the Swift files | Diff check runs on Linux, so no macOS runner is needed for #2 | Thousands of generated lines in PRs; a committed Swift file can be edited by hand and drift | Rejected |
| Fetch the spec from a running API at build time | Nothing to commit | Mobile builds depend on a live backend; macOS CI would have to run Node, Postgres and Redis; contract changes are invisible in review | Rejected |
| Put the macOS job in `deploy.yml` | One workflow | No per-job path filter, and a mobile failure would block backend deploys | Rejected |
| Keep hand-written DTOs plus fixtures | No new dependency | This is exactly the silent-drift problem ADR-005 flagged | Rejected |

## Consequences

### Positive
- A contract change becomes a visible `openapi.json` diff, and CI catches both an unsynced spec (#1) and Swift code it breaks (#2/#3). The ADR-005 risk is closed.
- The first mobile CI job exists, so ADR-025 §4 is implemented for unit tests.
- Generated types are Swift 6 / `Sendable`-ready and maintained by Apple.

### Negative / Risks
- **Response bodies are not documented yet.** The spec exposes only request DTOs (`CreateActivityRequestDto`, the webhook bodies). Responses such as `/v1/me` or `activitySummarySchema` are declared with no schema, because controllers don't attach their response Zod schemas to Swagger. Until they do, the generated types cover requests only. Wiring response schemas into the controllers (`nestjs-zod` / `@ApiOkResponse`) is the next step. *Amended by [ADR-029](ADR-029-activity-feed-and-card.md)*: started with `@ZodResponse` on `GET /v1/feed` and the kudos endpoints; other controllers follow when touched.
- **Better Auth routes (`/api/auth/*`) are outside the Nest spec**, so their DTOs stay hand-written in `APIAuthRepository`. Better Auth's `openAPI` plugin could close this later.
- **Plugin trust**: every CLI build needs `-skipPackagePluginValidation`, and each machine approves the plugin once in Xcode.
- **macOS runner cost and Xcode image drift**: this is mitigated by the path filter and `setup-xcode`, but `mobile:test` targets the `iPhone 17` simulator, which requires Xcode 26+ on the runner image.
- **Preview-mode export** depends on `@nestjs/swagger` reading route metadata without instantiated providers. If a future Nest or Swagger upgrade breaks this, the fallback is a regular `create()`, since the CI `test` job already provides Postgres and Redis.

## References
- [swift-openapi-generator](https://github.com/apple/swift-openapi-generator)
- [swift-openapi-runtime](https://github.com/apple/swift-openapi-runtime), [swift-openapi-urlsession](https://github.com/apple/swift-openapi-urlsession)
- [nestjs-zod](https://github.com/BenLorantfy/nestjs-zod) (`cleanupOpenApiDoc`)
- [XcodeGen `buildToolPlugins`](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)

## Links
- **Depends on**: [ADR-005](ADR-005-monorepo.md), [ADR-009](ADR-009-backend-api.md), [ADR-025](ADR-025-mobile-testing-strategy.md)
- **Amends**: [ADR-005](ADR-005-monorepo.md) (closes the OpenAPI → Swift risk), [ADR-009](ADR-009-backend-api.md) (Documentation row), [ADR-025](ADR-025-mobile-testing-strategy.md) (§4 mobile CI job implemented for unit tests)
- **Amended by**: [ADR-029](ADR-029-activity-feed-and-card.md) (first documented response bodies)
- **Related**: [ADR-002](ADR-002-mobile.md), [ADR-007](ADR-007-mobile-architecture.md), [ADR-018](ADR-018-docker-vps-deployment.md), [ADR-022](ADR-022-authentication-better-auth.md), [ADR-024](ADR-024-backend-testing-strategy.md)
