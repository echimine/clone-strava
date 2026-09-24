# ADR-012: Detailed backoffice stack

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: backoffice, nextjs, shadcn, frontend

## Context

ADR-004 set the main building blocks of the backoffice (Next.js, TypeScript, Tailwind CSS, shadcn/ui) and its principle: an API client, with no database access and no real-time. What remains is choosing the libraries for data, forms, tables, authentication and the map, and how to manage shadcn components in the monorepo.

The backoffice is an **internal tool**, in **French only**.

## Decision

| Need | Choice |
|---|---|
| Framework | **Next.js** (App Router), React 19, TypeScript |
| Styles | **Tailwind CSS v4** (configuration in CSS, shared theme variables) |
| Components | **shadcn/ui**, installed **via the shadcn MCP server** into **`packages/ui`** |
| Icons | **lucide-react** (shadcn's default library) |
| Server data | **TanStack Query v5**: cache, loading, invalidation after changes, retries |
| Forms | **React Hook Form** + **Zod** resolver, with the schemas from `packages/contracts` |
| Tables | **TanStack Table**, following shadcn's "data table" pattern |
| Authentication | **Better Auth** client (`better-auth/react`), cookie session |
| Map | **Mapbox GL JS** (`mapbox-gl`) |
| Charts | shadcn **Chart** components (based on Recharts) |
| On-screen notifications | **Sonner** (shadcn's `sonner` component) |
| Dates | **date-fns** with the `fr` locale |
| Language | **French only**, text written directly in the code, no i18n library |
| Tests | **Vitest** + **Testing Library**, **MSW** to mock the API |

### shadcn/ui: components in `packages/ui`, added via the MCP

- shadcn components live in **`packages/ui`**, shared across the monorepo (ADR-005). `apps/admin` imports them from `@repo/ui`.
- The project uses **shadcn's monorepo mode**: one `components.json` in `packages/ui` (component target) and one in `apps/admin`, with aliases to `@repo/ui/components`, `@repo/ui/lib` and `@repo/ui/hooks`.
- **Every component addition goes through the shadcn MCP server** (search, view, then install into `packages/ui`), configured in the repository's `.mcp.json`. We do not hand-write a component that exists in the shadcn registry.
- Global styles and theme variables (`globals.css`) are in `packages/ui` and imported by the app.
- Components in `packages/ui` stay **generic**: no API calls, no business knowledge (ADR-013).
- The current files in `packages/ui` (`button.tsx`, `card.tsx`, `code.tsx` from the create-turbo template) will be replaced by shadcn components.

### Map: Mapbox GL JS

- Same provider as mobile (ADR-002): **same Mapbox Studio styles**, consistent rendering between the app and the backoffice.
- Uses: display the route of a reported activity, **validate and correct segments**.
- **Client-only** component (dynamic loading without server rendering), specific to `apps/admin`: `mapbox-gl` does not go into `packages/ui`.
- Public Mapbox token dedicated to the backoffice, **restricted to the backoffice URLs**.

## Alternatives Considered

| Topic | Alternative | Why rejected |
|---|---|---|
| Components | shadcn components copied into each app | Duplication as soon as a second web app exists; `packages/ui` is already planned (ADR-005) |
| Components | Manual addition (copy-paste from the website) | The MCP guarantees the right version, the right dependencies and the right location |
| Server data | Hand-written `useEffect` + `fetch` | Cache, invalidation, retries and loading states to rewrite in every hook |
| Server data | SWR | Less complete for mutations and invalidation |
| Forms | Formik / hand-written uncontrolled forms | React Hook Form is the shadcn standard and integrates with Zod |
| Map | MapLibre GL JS | Styles and tiles to provide yourself; Mapbox keeps consistency with mobile |
| Map | Leaflet | No vector rendering or Mapbox styles |
| Language | next-intl from the start | Unnecessary for an internal French-language tool; can be added later |

## Consequences

### Positive
- A single place for components and the theme, reusable by a future web app.
- Forms validated on the client with the **same Zod schemas** as the API.
- Data always up to date after an action (TanStack Query invalidation), without repetitive code.
- Map identical to the mobile one.

### Negative / Risks
- **shadcn monorepo mode**: aliases and `components.json` must be configured correctly in both projects, otherwise the MCP installs to the wrong place.
- **Copied components**: shadcn updates are not automatic; we reinstall them via the MCP if needed.
- **Mapbox cost**: the backoffice also consumes map loads (low for internal use).
- **No i18n**: if the backoffice ever needs to be translated, the text will have to be extracted.

## References
- [ADR-004: Backoffice stack and architecture](ADR-004-backoffice.md)
- [ADR-013: Detailed backoffice architecture](ADR-013-backoffice-architecture.md)
- shadcn/ui monorepo: https://ui.shadcn.com/docs/monorepo
- shadcn/ui MCP: https://ui.shadcn.com/docs/mcp
- TanStack Query: https://tanstack.com/query
- React Hook Form: https://react-hook-form.com
- Mapbox GL JS: https://docs.mapbox.com/mapbox-gl-js/

## Links

- **Details**: [ADR-004](ADR-004-backoffice.md) (backoffice stack and architecture)
- **Related**: [ADR-005](ADR-005-monorepo.md), [ADR-009](ADR-009-backend-api.md), [ADR-013](ADR-013-backoffice-architecture.md)
