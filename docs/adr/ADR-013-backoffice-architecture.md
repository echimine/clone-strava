# ADR-013: Detailed backoffice architecture

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: backoffice, nextjs, architecture, frontend
- **Source**: Like-Strava architecture deck, slide 06 "Backoffice architecture"

## Context

ADR-004 sets the principle: organization by feature, a single HTTP client, flow Action → Hook → `api.ts` + `apiClient` → API → updated component. ADR-012 sets the libraries (TanStack Query, React Hook Form, shadcn in `packages/ui`, Mapbox GL JS). What remains is defining the full directory tree, the role of each element, authentication, communication with the API and error handling.

## Decision

### Directory tree

```
apps/admin/src/
├── app/
│   ├── (auth)/login/page.tsx               sign-in
│   ├── (admin)/
│   │   ├── layout.tsx                      checks the session and role, displays the navigation
│   │   ├── page.tsx                        dashboard
│   │   ├── users/page.tsx
│   │   ├── users/[id]/page.tsx
│   │   ├── activities/page.tsx
│   │   ├── activities/[id]/page.tsx
│   │   └── segments/…
│   └── error.tsx, not-found.tsx
├── features/
│   └── activities/
│       ├── components/                     ActivityTable, ActivityDetail… (built from @repo/ui)
│       ├── hooks/                          useActivities, useActivity, useDeleteActivity
│       ├── lib/                            pure utilities (e.g. parseGpx)
│       ├── api.ts                          typed functions per endpoint
│       └── query-keys.ts                   the feature's TanStack Query cache keys
├── components/                             app-specific elements: navigation, header, MapView (Mapbox)
├── lib/
│   ├── apiClient.ts                        single HTTP client
│   ├── queryClient.ts                      TanStack Query configuration
│   └── auth-client.ts                      Better Auth client
└── proxy.ts                                redirect to /login without a session cookie
```

Features planned for the MVP (indicative): `dashboard`, `users`, `activities`, `segments`, `moderation`.

### Where to put a component

| Location | Content | Example |
|---|---|---|
| `packages/ui` | shadcn components and generic components, with no business logic or API calls | `Button`, `DataTable`, `ConfirmDialog`, `PageHeader` |
| `apps/admin/src/components` | Backoffice-specific elements, shared across features | Navigation, `MapView` (Mapbox) |
| `features/<feature>/components` | Components of a feature | `ActivityTable`, `SegmentEditor` |

### Flow of an admin action

```
Admin action → Hook (TanStack Query) → api.ts → apiClient → NestJS API → cache invalidation → updated component
```

| Element | Role | Forbidden |
|---|---|---|
| `page.tsx` | Route: layout, reading URL parameters, assembling the feature's components | Loading data, calling the API |
| Feature component | Displays, triggers actions via its hooks | Calling `api.ts` or `apiClient` |
| Hook | `useQuery` to read, `useMutation` to modify; invalidates the relevant keys after a change; shows a success or error toast | Direct `fetch` |
| `api.ts` | One typed function per endpoint, with types from `packages/contracts` | Holding state |
| `query-keys.ts` | The feature's hierarchical cache keys (`['activities', 'list', filters]`, `['activities', id]`) | — |
| `lib/apiClient.ts` | Base URL, session cookie, JSON, response validation, normalized errors | Knowing business logic |

### Communication with the API: same origin via the Next.js proxy

- The browser calls **`/api/...` on the backoffice domain**; Next.js forwards these requests to the NestJS API (rewrites in `next.config`).
- Benefits: **no CORS**, the **Better Auth cookie** stays on the backoffice domain, the API URL is not exposed to the browser. *Amended by [ADR-022](ADR-022-authentication-better-auth.md)*: the cookie is scoped to `.strava.echimine.fr` (`crossSubDomainCookies`), not narrowly to the backoffice's own subdomain, so a future web app on another subdomain shares the session.
- The proxy only forwards: no logic, no database writes (ADR-004).

### Authentication and authorization

1. **`proxy.ts`** (Next.js middleware): without a session cookie, redirect to `/login`. A UI convenience only.
2. **`(admin)` layout**: fetches the current user through the API (`GET /v1/me`); if the session is invalid → `/login`, if the user is not an administrator → "access denied" page.
3. **The API remains the sole guarantor**: every administration endpoint checks the role (ADR-009). Steps 1 and 2 only improve the experience.
4. Sign-in and sign-out via the Better Auth client (`lib/auth-client.ts`).

### Errors

| Situation | Handling |
|---|---|
| `401` | Redirect to `/login` (in `apiClient`) |
| `403` | "Access denied" message |
| `422` / validation error | Errors shown under the form fields, based on the details returned by the API (single error format, ADR-009) |
| Other error on a modification | Error toast (Sonner) |
| Page loading error | The segment's `error.tsx`, with a "retry" button |

### Tables and filters

- Pagination, sorting and filters **server-side** (the API returns one page at a time).
- Filter and pagination state is **in the URL** (search parameters): a filtered view can be shared or reloaded.

### Rules

1. **No direct access** to PostgreSQL, Redis or the bucket: no `drizzle-orm`, `pg`, `ioredis` or S3 SDK dependency in `apps/admin` (ESLint rule `no-restricted-imports`).
2. **Every network call goes through `apiClient`.**
3. **A feature does not import another feature** (ESLint rule). Anything shared moves up into `src/components`, `src/lib` or `packages/ui`.
4. **`packages/ui` does not depend on the app**: no import from `apps/admin`, no API calls.
5. Types and schemas for exchanges come **only from `packages/contracts`**.

### Tests

| Target | Tool |
|---|---|
| Hooks and `api.ts` | Vitest + MSW (mocked API) |
| Feature components | Testing Library + MSW |
| Utilities (`lib/`) | Vitest |

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Direct calls from the browser to the API (different domain) | CORS and cross-domain cookie configuration to handle |
| Loading data in Server Components | Diverges from the slide 06 flow (hooks); TanStack Query handles cache and invalidation better for a highly interactive tool |
| Server Actions | Logic on the Next.js side instead of the API; risk of bypassing business rules |
| Split by file type (`components/`, `hooks/` at the root) | A feature scattered across the whole project |
| Filters kept in memory | Lost on reload, views not shareable |

## Consequences

### Positive
- A feature can be read in a single folder; routes stay thin.
- No CORS or cross-domain cookies thanks to the proxy.
- Authorization centralized in the API.
- Consistent data after every action thanks to per-feature cache keys.

### Negative / Risks
- **Next.js proxy**: one more network hop between the browser and the API (negligible for an internal tool); headers (IP, correlation ID) must be forwarded correctly.
- **Client-side loading**: first render with a loading state.
- **ESLint rules** to set up from the start so the prohibitions are checked automatically.

## References
- Like-Strava architecture deck, slide 06
- [ADR-004: Backoffice stack and architecture](ADR-004-backoffice.md)
- [ADR-009: Backend · api app](ADR-009-backend-api.md)
- [ADR-012: Detailed backoffice stack](ADR-012-backoffice-stack.md)
- TanStack Query, query keys: https://tanstack.com/query/latest/docs/framework/react/guides/query-keys

## Links

- **Details**: [ADR-004](ADR-004-backoffice.md)
- **Related**: [ADR-009](ADR-009-backend-api.md), [ADR-012](ADR-012-backoffice-stack.md), [ADR-022](ADR-022-authentication-better-auth.md) (cookie scope)
