# ADR-020: MCP servers for the development assistant

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: tooling, mcp, ai-assistant

## Context

Development is done with an AI assistant (Claude Code). Without access to the project's tools, the assistant works from memory: sometimes outdated documentation, components copied by hand, guessed iOS build errors, assumed database schema. **MCP** (Model Context Protocol) servers give it direct, up-to-date access to these tools.

## Decision

**The assistant always uses the appropriate MCP server when one exists**, rather than working from memory or reproducing by hand what the tool does.

### Selected servers

| Server | Mandatory use | Related ADRs | Scope | State |
|---|---|---|---|---|
| **Context7** | Any question about a library, framework or SDK (NestJS, Drizzle, BullMQ, Better Auth, Next.js, TanStack Query, GRDB, Mapbox…): check the up-to-date documentation before writing code | All | Local | Active |
| **shadcn** | Search, view and **add** any shadcn component in `packages/ui`; never copy manually | ADR-012 | **Project** (`.mcp.json`, versioned) | Active |
| **MobileBuildMCP** (formerly XcodeBuildMCP) | Build, test and run the iOS app on the simulator, read build errors, screenshots; preferred over `xcodebuild` commands | ADR-006, ADR-007 | Local | Active |
| **Postgres MCP Pro** | Read the schema, run read queries, analyze execution plans and indexes (including PostGIS), **read-only** (`--access-mode=restricted`) | ADR-017 | Local | Waiting for the development database (`docker-compose.dev.yml`) |
| **Redis** | Inspect BullMQ queues, keys and Pub/Sub while debugging the worker and realtime | ADR-010, ADR-011 | Local | Active (useful once the development Redis is running) |
| **Mapbox** (hosted) | Geocoding, directions, static maps, Mapbox documentation | ADR-006, ADR-012 | Local | **To authenticate** (`/mcp` → mapbox) |
| **PostHog** (hosted) | Create and read feature flags and experiments, query events | ADR-015, ADR-016 | Local | **To authenticate** (`/mcp` → posthog) |

Additional tools already available: **Figma** (mockups), **Claude in Chrome** (manual testing of the backoffice).

Docker deployment does not go through an MCP but through the **`deploy-vps` skill and agent** (ADR-018).

### Rules

1. **Always** go through the appropriate MCP when it covers the need (documentation, components, iOS build, database, Redis, analytics, maps).
2. **Never any secret in `.mcp.json`**, which is versioned. Only servers without secrets are listed there (shadcn). The others are configured in **local** scope (`~/.claude.json`) or **user** scope.
3. **Postgres and Redis only on the local development environment**. Never production VPS credentials in an MCP.
4. Postgres always **read-only** (`--access-mode=restricted`); schema changes go through Drizzle migrations.
5. Any API keys go through **environment variables** (`-e`), never as a command argument (they would be shown in plain text in `claude mcp list`).
6. A new MCP server is added to this table (update of this ADR).

### Pending actions

- [ ] **Mapbox**: authenticate the server (`/mcp` → mapbox, log in to the Mapbox account).
- [ ] **PostHog**: authenticate the server (`/mcp` → posthog, log in to the PostHog EU account).
- [ ] **Postgres**: align the address `postgresql://strava:strava@localhost:5432/strava` with the credentials in `docker-compose.dev.yml`.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| No MCP, the assistant works from memory | Outdated documentation, API errors, components copied by hand |
| All servers in the versioned `.mcp.json` | Would expose credentials (database, API keys) in the repository |
| Postgres in read-write mode | Risk of modifying the database outside migrations |

## Consequences

### Positive
- Code written from up-to-date documentation and the actual state of the project.
- shadcn components always added in the right place, in the right version.
- Faster iOS development loop (build, test, screenshots from the assistant).

### Negative / Risks
- Dependency on third-party servers (hosted or downloaded on the fly); in case of an outage, fall back to working without MCP.
- Local configuration per developer (outside the repository): to be redone on each machine, following this ADR.
- Servers downloaded via `npx` / `uvx` at `latest`: a new version can change behavior.

## References
- Model Context Protocol: https://modelcontextprotocol.io
- Context7: https://github.com/upstash/context7
- shadcn MCP: https://ui.shadcn.com/docs/mcp
- MobileBuildMCP: https://github.com/getsentry/XcodeBuildMCP
- Postgres MCP Pro: https://github.com/crystaldba/postgres-mcp
- Redis MCP: https://github.com/redis/mcp-redis
- Mapbox MCP: https://github.com/mapbox/mcp-server
- PostHog MCP: https://posthog.com/docs/model-context-protocol

## Links

- **Related**: [ADR-006](ADR-006-mobile-stack.md), [ADR-010](ADR-010-backend-realtime.md), [ADR-011](ADR-011-backend-worker.md), [ADR-012](ADR-012-backoffice-stack.md), [ADR-015](ADR-015-posthog.md), [ADR-017](ADR-017-data-model.md), [ADR-018](ADR-018-docker-vps-deployment.md)
