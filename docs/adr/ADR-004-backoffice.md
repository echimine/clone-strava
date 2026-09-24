# ADR-004: Backoffice stack and architecture

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: backoffice, nextjs, shadcn, admin
- **Source**: Like-Strava architecture deck, slides 05 "Stack · backoffice" and 06 "Backoffice architecture"

## Context

The platform needs a web administration application, restricted to the team: user management, content moderation, segment management, platform monitoring. The priority is development productivity and standard management screens (tables, forms, filters, dialogs).

## Decision

### Stack

| Building block | Choice | Role |
|---|---|---|
| Framework | **Next.js** (App Router) | Web application |
| Language | **TypeScript** | Typed code |
| Styles | **Tailwind CSS** | Utility styles |
| Components | **shadcn/ui** | Administration components, copied into the code and editable |

### Principles

1. **The backoffice is a client of the API**, like the mobile app (ADR-001). It **never directly contacts PostgreSQL**, nor Redis.
2. **Administrator role checked by the API** on every administration endpoint (Better Auth, ADR-003). Page protection on the Next.js side improves the experience but does not constitute security.
3. **No real time**: the backoffice is connected only to the API (ADR-001).

### Architecture: organization by feature

```
src/
├── app/admin/<feature>/page.tsx      route: layout and assembly
├── features/<feature>/
│   ├── components/                   feature UI (shadcn/ui)
│   ├── hooks/                        the "controller": state, loading, actions
│   ├── lib/                          feature-specific utilities (e.g. parseGpx)
│   └── api.ts                        typed API calls for the feature
└── lib/apiClient.ts                  single HTTP client to the API
```

Flow of an admin action:

```
Administrator action → Hook (controller) → api.ts + apiClient → NestJS API → Component updated
```

- Every network call goes through `lib/apiClient.ts` (base URL, session, normalized errors).
- A feature does not import another feature.
- DTOs are typed from `packages/contracts` (ADR-005).

The details (data loading, caching, error handling) will be specified in a dedicated ADR.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Generated admin (AdminJS, React Admin) | Plugged into the database or into imposed API conventions, bypasses the business rules |
| Low-code tool (Retool, Appsmith) | SaaS dependency, per-user cost, data access outside our code |
| Server Actions with direct database access | Bypasses the API and its rules (contradicts ADR-001) |
| MUI / Ant Design | Theme heavy to customize, strong dependency |

## Consequences

### Positive
- Business and access rules centralized in the API: the admin cannot do anything the API does not allow.
- Same language as the backend, shared Zod contracts.
- Same feature-based split as the mobile app and the backend.

### Negative / Risks
- **Administration endpoints to develop** in the API for each need.
- **Security**: log administration actions (who, what, when), eventually plan for two-factor authentication.
- **Exposure**: `noindex`, and possible network restriction (dedicated subdomain, IP allowlist).
- **CORS and cookies**: avoided thanks to the Next.js proxy to the API (ADR-013).

## References
- Like-Strava architecture deck, slides 05 and 06
- [ADR-001: Global architecture](ADR-001-global-architecture.md)
- [ADR-003: Backend](ADR-003-backend.md)
- Next.js: https://nextjs.org/docs
- shadcn/ui: https://ui.shadcn.com

## Links

- **Depends on**: [ADR-001](ADR-001-global-architecture.md), [ADR-003](ADR-003-backend.md)
