# ADR-005 : Monorepo Turborepo

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : dossier d'architecture Like-Strava, slide 07 « Monorepo »
- **En lien avec** : [ADR-002](ADR-002-mobile.md), [ADR-003](ADR-003-backend.md), [ADR-004](ADR-004-backoffice.md)

## Contexte

Le projet regroupe trois projets : l'app mobile (Swift), le backend (3 apps NestJS, ADR-003) et le backoffice (Next.js, ADR-004). Le backend et le backoffice partagent des contrats (DTO, événements) et le backend partage du métier entre ses trois apps. Le dépôt est déjà initialisé avec Turborepo et pnpm (template create-turbo).

## Décision

**Les trois projets vivent dans un seul dépôt, géré par Turborepo et pnpm workspaces.**

```
strava-app/
├── apps/
│   ├── api/          REST (NestJS)
│   ├── realtime/     WebSocket (NestJS)
│   ├── worker/       jobs BullMQ (NestJS)
│   ├── admin/        backoffice (Next.js)
│   └── mobile/       app iOS (Xcode)
└── packages/
    ├── contracts/    schémas Zod partagés (DTO, données des jobs, événements)
    ├── ui/           composants UI partagés
    ├── db/           schéma Drizzle, client, migrations (ADR-003)
    ├── core/         modules métier partagés par api, realtime et worker (ADR-003)
    ├── realtime/     protocole temps réel, topics, publieur Redis (ajouté par ADR-010)
    ├── eslint-config/       (existant)
    └── typescript-config/   (existant)
```

### Principes

- **`packages/contracts` est la source de vérité des échanges** : l'API valide ses entrées avec ces schémas, le backoffice s'en sert pour typer ses appels, le worker et le serveur WS pour les jobs et les événements.
- **Les dépendances vont des apps vers les packages**, jamais d'une app vers une autre app.
- **Turborepo orchestre** `build`, `lint`, `check-types` et `dev`, avec cache et ordre de build selon les dépendances (`^build`).
- **`apps/mobile`** (projet Xcode, Swift Package Manager) est dans le dépôt mais **hors du workspace pnpm et du pipeline Turbo** : Zod n'est pas utilisable en Swift. Les modèles réseau Swift seront **générés depuis une spec OpenAPI** exposée par l'API et dérivée des contrats.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Un dépôt par projet (polyrepo) | Contrats à publier et versionner séparément, changements transverses en plusieurs PR |
| Nx | Plus complet mais plus lourd ; Turborepo est déjà en place et suffit |
| Mobile dans un dépôt séparé | Perte de la vue d'ensemble et de la synchronisation des changements d'API ; le garder dans le dépôt n'impose pas de l'intégrer à Turbo |

## Conséquences

### Positives
- Un changement d'API (contrat, endpoint, client) se fait en une seule PR.
- Types partagés entre backend et backoffice sans publication de packages.
- Cache Turborepo : seules les apps impactées sont reconstruites.

### Négatives / risques
- **Deux chaînes d'outillage** (pnpm/Turbo et Xcode) dans le même dépôt ; la CI doit les traiter séparément.
- **Génération OpenAPI → Swift** à mettre en place pour que le mobile suive les contrats.
- **Packages compilés** (`core`, `db`) : configuration de build à soigner (voir ADR-003).
- **Nettoyage du template** : `apps/web` et `apps/docs` (exemples create-turbo) seront supprimés ou réaffectés lors de la mise en place des apps.

## Références
- Dossier d'architecture Like-Strava, slide 07
- [ADR-003 : Backend](ADR-003-backend.md)
- Turborepo : https://turborepo.com/docs
