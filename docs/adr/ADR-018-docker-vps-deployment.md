# ADR-018: Dockerization and VPS deployment

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: deployment, docker, vps, ci-cd
- **Source**: echimine in-house deployment pattern (GHCR → webhook → VPS), `deploy-vps` skill

## Context

All server apps in the monorepo must run in Docker containers on the **OVH GRA-01 VPS**, which already hosts other apps behind Traefik with an established deployment pattern: images built by GitHub Actions, pushed to GHCR, then pulled by the VPS when a webhook is called.

What sets this project apart from the existing apps:
- **4 application images** (`api`, `realtime`, `worker`, `admin`) in a **pnpm + Turborepo monorepo** with internal packages;
- **PostGIS** and **Redis** (BullMQ queues, Pub/Sub);
- **long-lived WebSocket connections** (`realtime`);
- a **worker without an HTTP server**;
- `apps/mobile` (Xcode project) is **outside Docker**.

## Decision

### 1. Deployment pattern

```
push main ─► GitHub Actions (matrix 4 apps) ─► build ─► ghcr.io/echimine/strava-<app>:<sha> + :latest
                                                            │
                     webhook (behind Traefik, X-Deploy-Token header) ─► hook deploy-strava
                                                            │
                     VPS: /opt/www/strava.echimine.fr/prod ─► docker compose pull && up -d
                                                            │
                     wait for all services to be "healthy" ─► Discord notification
```

- **Registry**: private GHCR, images `ghcr.io/echimine/strava-{api,realtime,worker,admin}`, tags **commit SHA** and `latest`. Push with the ephemeral `GITHUB_TOKEN`.
- **Trigger**: webhook, no SSH from GitHub. Token **specific to this app** (`DEPLOY_WEBHOOK_SECRET`).
- **VPS**: read-only GHCR login, a single **`prod`** environment in `/opt/www/strava.echimine.fr/prod/` (`docker-compose.yml`, `.env` with `chmod 600`).
- **Rollback**: pin the 4 images to a previous SHA.

### 2. Domains

| Service | Domain | Exposed |
|---|---|---|
| `api` | `api.strava.echimine.fr` | Yes (Traefik, HTTPS) |
| `realtime` | `ws.strava.echimine.fr` (`wss://…/ws`) | Yes (Traefik, WebSocket) |
| `admin` | `admin.strava.echimine.fr` | Yes (Traefik, HTTPS) |
| `worker` | — | **No**: no HTTP server, nothing to expose |
| `db`, `redis` | — | **No**: internal networks only |

### 3. Docker images

**NestJS apps (`api`, `realtime`, `worker`)**: multi-stage Dockerfile.

| Stage | Role |
|---|---|
| `pruner` | `turbo prune <app> --docker`: keeps only the app, its internal packages and a pruned lockfile |
| `builder` | `pnpm install --frozen-lockfile`, then build via Turborepo, **in the same stage**; then `pnpm deploy --prod` produces a self-contained `node_modules` without dev dependencies |
| `runner` | `node:24-alpine`, **`node` user (non-root)**, copies only the output of `pnpm deploy` |

- **Pinned pnpm version** (`pnpm@11.25.0`, the one from `packageManager`), installed explicitly.
- **Main process = `node`** (`CMD ["node", "dist/main.js"]`), never `pnpm start`, which does not forward `SIGTERM`.
- If a native module causes trouble under Alpine (musl), switch to `node:24-bookworm-slim`.

**Admin (Next.js)**: **`standalone`** output, `outputFileTracingRoot` at the monorepo root, `transpilePackages: ['@repo/ui']`, `HOSTNAME=0.0.0.0`, non-root user.

**Internal packages**: `core`, `db`, `contracts` and `realtime` are **compiled** (`dist/`), because NestJS decorators do not run from source. `packages/db` also ships the migrations folder. `packages/ui` stays as source (consumed only by the admin).

### 4. Migrations

- Run **at api startup**: the entrypoint runs `migrate()` (Drizzle, compiled in `packages/db`), then `exec node dist/main.js`.
- The `worker` and the `admin` wait for the api to be "healthy", and therefore for the migrations to have run.
- The api stays at **a single instance**. If it needs to scale to several, migrations will become a dedicated one-off service.

### 5. Services, networks and volumes

| Service | Image | Networks | Volume |
|---|---|---|---|
| `db` | `postgis/postgis:17-3.5` (pinned version) | `data` | `db-data` |
| `redis` | `redis:7-alpine` | `data` | `redis-data` |
| `api` | `strava-api` | `traefik-public`, `data`, `admin-api` | — |
| `realtime` | `strava-realtime` | `traefik-public`, `data` | — |
| `worker` | `strava-worker` | `data`, `egress` | — |
| `admin` | `strava-admin` | `traefik-public`, `admin-api` | — |

| Network | Type | Role |
|---|---|---|
| `traefik-public` | External, shared between the VPS apps | HTTPS exposure via Traefik |
| `data` | Internal (no Internet) | Access to PostgreSQL and Redis |
| `admin-api` | Internal | Admin proxy to the api (`http://api:3001`), without going through the shared network |
| `egress` | Standard bridge, not exposed | Internet egress for the worker (OVH bucket, RevenueCat, PostHog) |

Rules for all services:
- **no published `ports:`**; exposure only via Traefik labels;
- `security_opt: no-new-privileges:true`;
- `restart: unless-stopped`;
- environment variables **declared per service** (each one only receives what it needs), values only in the VPS `.env`;
- Traefik router names prefixed with `strava-` (unique on the VPS);
- `container_name` only on `db` (used by the backup script); **never on `realtime` or `worker`**, so that several instances can be run;
- Docker log rotation configured (`max-size`, `max-file`): Pino logs are voluminous.

**Redis**: `--appendonly yes --appendfsync everysec --maxmemory-policy noeviction` (mandatory for BullMQ), password via a mounted configuration file (not as a command argument, which is visible in `docker inspect`).

### 6. Health and graceful shutdown

| Service | Healthcheck | `stop_grace_period` |
|---|---|---|
| `api` | `GET /health` (database + Redis), public route outside `/v1`, excluded from rate limiting and authentication | 15 s |
| `realtime` | `GET /health` | 15 s (closes connections with `4009`) |
| `worker` | **heartbeat file** `/tmp/worker-alive` updated every 15 s as long as Redis and the BullMQ workers are ready | 120 s (finishes in-progress jobs), to be adjusted to the maximum duration of a job |
| `admin` | `GET /login`, code < 500 | 10 s |
| `db` | `pg_isready` | 30 s |
| `redis` | `redis-cli ping` | 30 s |

- `init: true` on the Node services, to forward signals correctly.
- NestJS: `enableShutdownHooks()`; the realtime app closes its connections with `4009`, the worker waits for its jobs to finish (`worker.close()`).

### 7. Backups

- **PostgreSQL**: existing generic script `/opt/backups/backup-db.sh`, wired through a systemd service and timer `backup-strava-db` (every night), to the backup bucket (30-day retention). **Restore tested** in a throwaway database (check the `postgis` extension, the geometry tables and the GiST indexes).
- **Redis: no external backup.** It only holds queues and transient events; the source of truth is PostgreSQL. AOF protects against a restart. If the volume is lost, a **reconciliation job** re-enqueues activities that stayed `pending` or `processing` for too long (partial index planned in ADR-017).
- **Assets bucket** (tracks, media): created with **an S3 user specific to the app**, never with the backup user, with a policy limited to that bucket.

### 8. Local development

- `docker-compose.dev.yml` with **only `db` and `redis`**, same images and options as in production, ports bound to `127.0.0.1`.
- The apps run on the machine with `pnpm dev` (hot reload).
- Optional `apps` profile to build and run the 4 images locally before a push.
- One `.env.example` per app (variable names only).

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Deployment via SSH from GitHub Actions | A privileged SSH key on the GitHub side; the webhook is the pattern already in place |
| Building images on the VPS | Consumes the production server's resources, no shared build cache |
| A single image for the 3 NestJS apps | Heavier images, coupled deployments and sizing; contrary to ADR-003 |
| WebSocket on `api.strava…/ws` (path-based routing) | More fragile Traefik rule; the dedicated subdomain isolates WebSocket traffic |
| `staging` environment on the VPS | Doubles the containers; testing goes through the local compose |
| Kubernetes / orchestrator | Overkill for a single VPS |
| External Redis backup | Transient data; reconciliation from PostgreSQL is enough |

## Consequences

### Positive
- Same pattern as the other VPS apps: tooling, webhook, Traefik and backups reused.
- Lightweight, reproducible images thanks to `turbo prune` and `pnpm deploy`.
- No directly exposed service; database and Redis unreachable from the Internet.
- Each app deploys and scales independently.

### Negative / Risks
- **TypeScript 7 and NestJS**: the Nest CLI relies on the TypeScript compiler API, which is absent from TS 7. To be checked at project start; likely solution: **SWC** build for the NestJS apps and packages, or TypeScript 5.x for those.
- **`turbo prune` with pnpm 11**: lockfile compatibility to be checked; build scripts of native dependencies (`msgpackr-extract`, `sharp`, `@swc/core`) must be explicitly allowed in pnpm.
- **Next.js proxy**: rewrite destinations are fixed at build time; the `http://api:3001` target is fixed via the `admin-api` network.
- **`trust proxy`**: must be enabled in Express, otherwise rate limiting sees all clients with Traefik's IP.
- Traefik **WebSocket timeout** (60 s read by default): to be tested; a change would affect the Traefik configuration shared by all apps.
- **Every deployment drops WebSocket connections** (`4009`): the mobile app reconnects (ADR-008).
- **Deployment duration**: 4 images, migrations and worker shutdown must fit within the deployment script's timeout (300 s).
- **Apple Silicon**: check `arm64` availability of the PostGIS image for local development.

## Implementation

### Mandatory tooling: `deploy-vps` skill and agent

The whole implementation of this ADR (Dockerfiles, `.dockerignore`, `deploy.yml`, compose, webhook, backups, VPS-side steps) **is done with the `deploy-vps` skill and the `deploy-vps` agent**, which carry the in-house pattern and its known pitfalls:

| Tool | Role | When to use it |
|---|---|---|
| **`deploy-vps` skill** (`/deploy-vps`) | Loads the GHCR → webhook → VPS pattern, the non-negotiable rules, the templates (`Dockerfile.nextjs-standalone`, `Dockerfile.node-migrations-entrypoint`, `docker-compose.yml`, `deploy.yml`, `hooks.json`, `deploy.sh`, `.dockerignore`) and the checklist | First, before creating or modifying any deployment file |
| **`deploy-vps` agent** | Inspects the repo, generates the files from the templates while adapting them to the monorepo, and lists the files and steps to do on the VPS side; never touches secrets | To generate or evolve the Docker and CI/CD files, and for every new app or new service to deploy |

Rules:
- **Do not hand-write** a Dockerfile, a compose file or a deployment workflow without going through the skill and the agent: the templates and known pitfalls (package manager pinning, healthcheck on a protected route, webhook, backups) are already built in.
- The **templates and reference documentation** live in the echimine documentation repository (`echimine-doc`): `vps/` sheets, ADRs `0001` and `0002`, skill templates.
- The project-specific deviations described above (pnpm and `turbo prune`, PostGIS, Redis, WebSocket, worker without HTTP, `admin-api` and `egress` networks) are given to the agent as context, along with this ADR.
- After the first deployment, the agent updates the echimine documentation (the app's deployment sheet, modeled on the existing apps).

### Files and steps

**In the repo** (after approval): 4 Dockerfiles, `.dockerignore` (excludes `apps/mobile`, `node_modules`, `.next`, `dist`, `.turbo`, `.git`, `.env*`, `docs`), `.github/workflows/deploy.yml` (matrix 4 apps), `docker-compose.dev.yml`, Next.js configuration for the admin, `dist/**` outputs in `turbo.json`, migration script in `packages/db`, worker heartbeat, NestJS shutdown hooks, up-to-date `pnpm-lock.yaml` committed.

**GitHub secrets**: `DEPLOY_WEBHOOK_SECRET`; `NEXT_PUBLIC_MAPBOX_TOKEN` (restricted public token) as a variable. No application secret in GitHub.

**OVH DNS**: `api.strava`, `ws.strava`, `admin.strava` pointing to the VPS IP.

**On the VPS**:
- folder `/opt/www/strava.echimine.fr/prod/` with `docker-compose.yml`, `.env` (600), Redis configuration;
- read-only GHCR access to the 4 images;
- `deploy-strava` hook (dedicated token), deployment script (`EXPECTED_SERVICES="db redis api worker realtime admin"`), folder mounted into the webhook container;
- first deployment: all services "healthy", `/health` over HTTPS, WebSocket connection lasting more than 2 minutes, login to the backoffice, `postgis` extension present;
- rollback tested;
- assets bucket with a dedicated user;
- PostgreSQL backup wired and restore tested;
- deployment sheet added to the echimine documentation.

## References
- echimine documentation: ADR `0001-deploiement-ghcr-webhook-vps`, `0002-backups-buckets-separes`; sheets `procedure-cicd-nextjs-ghcr.md`, `vps-ovh-gra-01-backups.md`, `vps-ovh-gra-01-traefik.md`
- Turborepo and Docker: https://turborepo.com/docs/guides/tools/docker
- pnpm deploy: https://pnpm.io/cli/deploy
- Next.js standalone: https://nextjs.org/docs/app/api-reference/config/next-config-js/output
- PostGIS image: https://hub.docker.com/r/postgis/postgis

## Links

- **Related**: [ADR-001](ADR-001-global-architecture.md), [ADR-003](ADR-003-backend.md), [ADR-005](ADR-005-monorepo.md), [ADR-009](ADR-009-backend-api.md), [ADR-010](ADR-010-backend-realtime.md), [ADR-011](ADR-011-backend-worker.md), [ADR-013](ADR-013-backoffice-architecture.md), [ADR-017](ADR-017-data-model.md)
