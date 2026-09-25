# ADR-005: Turborepo monorepo

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: monorepo, turborepo, pnpm, tooling
- **Source**: Like-Strava architecture deck, slide 07 "Monorepo"

## Context

The project brings together three projects: the mobile app (Swift), the backend (3 NestJS apps, ADR-003) and the backoffice (Next.js, ADR-004). The backend and the backoffice share contracts (DTOs, events) and the backend shares business logic between its three apps. The repository is already initialized with Turborepo and pnpm (create-turbo template).

## Decision

**The three projects live in a single repository, managed by Turborepo and pnpm workspaces.**

```
strava-app/
├── apps/
│   ├── api/          REST (NestJS)
│   ├── realtime/     WebSocket (NestJS)
│   ├── worker/       BullMQ jobs (NestJS)
│   ├── admin/        backoffice (Next.js)
│   └── mobile/       iOS app (Xcode)
└── packages/
    ├── contracts/    shared Zod schemas (DTOs, job data, events)
    ├── ui/           shared UI components
    ├── db/           Drizzle schema, client, migrations (ADR-003)
    ├── core/         business modules shared by api, realtime and worker (ADR-003)
    ├── realtime/     real-time protocol, topics, Redis publisher (added by ADR-010)
    ├── eslint-config/       (existing)
    └── typescript-config/   (existing)
```

### Principles

- **`packages/contracts` is the source of truth for exchanges**: the API validates its inputs with these schemas, the backoffice uses them to type its calls, the worker and the WS server for jobs and events.
- **Dependencies go from apps to packages**, never from one app to another app.
- **Turborepo orchestrates** `build`, `lint`, `check-types` and `dev`, with caching and build order based on dependencies (`^build`).
- **`apps/mobile`** (Xcode project, Swift Package Manager) is in the repository but **outside the pnpm workspace and the Turbo pipeline**: Zod cannot be used in Swift. The Swift network models will be **generated from an OpenAPI spec** exposed by the API and derived from the contracts.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| One repository per project (polyrepo) | Contracts to publish and version separately, cross-cutting changes across several PRs |
| Nx | More complete but heavier; Turborepo is already in place and is sufficient |
| Mobile in a separate repository | Loss of the overall view and of the synchronization of API changes; keeping it in the repository does not require integrating it into Turbo |

## Consequences

### Positive
- An API change (contract, endpoint, client) is made in a single PR.
- Types shared between backend and backoffice without publishing packages.
- Turborepo cache: only the affected apps are rebuilt.

### Negative / Risks
- **Two toolchains** (pnpm/Turbo and Xcode) in the same repository; CI must handle them separately.
- **OpenAPI → Swift generation** to set up so that the mobile app follows the contracts. *Amended by [ADR-026](ADR-026-openapi-swift-codegen.md)*: done — `swift-openapi-generator` build plugin on a committed `openapi.json`, with drift and contract checks in CI.
- **Compiled packages** (`core`, `db`): build configuration needs care (see ADR-003).
- **Template cleanup**: `apps/web` and `apps/docs` (create-turbo examples) will be removed or repurposed when the apps are set up.

## References
- Like-Strava architecture deck, slide 07
- [ADR-003: Backend](ADR-003-backend.md)
- Turborepo: https://turborepo.com/docs

## Links

- **Related**: [ADR-002](ADR-002-mobile.md), [ADR-003](ADR-003-backend.md), [ADR-004](ADR-004-backoffice.md)
- **Amended by**: [ADR-010](ADR-010-backend-realtime.md) (adds `packages/realtime`), [ADR-026](ADR-026-openapi-swift-codegen.md) (OpenAPI → Swift generation implemented)
