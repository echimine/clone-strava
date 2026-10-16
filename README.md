# Nervo

Monorepo Turborepo + pnpm (ADR-005). Les décisions d'architecture sont dans [`docs/adr/`](docs/adr).

## Contenu

| Chemin | Rôle |
|---|---|
| `apps/api` | API REST NestJS (ADR-009), port 3001 |
| `apps/worker` | Jobs BullMQ NestJS, sans serveur HTTP (ADR-011) |
| `apps/realtime` | Passerelle WebSocket NestJS, port 3003 (ADR-010) |
| `apps/admin` | Backoffice Next.js, port 3002 (ADR-012, ADR-013) |
| `apps/mobile` | App iOS SwiftUI, hors workspace pnpm (ADR-006, ADR-007) |
| `packages/contracts` | Schémas Zod partagés : DTO, jobs, événements |
| `packages/db` | Schéma Drizzle, un schéma PostgreSQL par module, migrations |
| `packages/core` | Modules métier NestJS partagés par api et worker (ADR-021) |
| `packages/realtime` | Protocole temps réel, topics, publisher Redis |
| `packages/ui` | Composants shadcn/ui, ajoutés via le MCP shadcn |

## Démarrer

```sh
pnpm install
pnpm db:up                                   # PostGIS + Redis (docker-compose.dev.yml)
pnpm --filter @repo/db build
DATABASE_URL=postgresql://strava:strava@localhost:5432/strava pnpm --filter @repo/db db:migrate
pnpm dev
```

Chaque app lit un fichier `.env` local (voir les variables dans `packages/contracts/src/config/env.ts`).

App iOS :

```sh
cd apps/mobile
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
xcodegen generate
```

## Vérifications

```sh
pnpm build
pnpm check-types
pnpm lint
pnpm test
pnpm check-deps:run   # frontières de modules (dependency-cruiser, ADR-021 §9)
```
