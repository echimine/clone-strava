# ADR-020 : Serveurs MCP de l'assistant de développement

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **En lien avec** : [ADR-006](ADR-006-stack-mobile.md), [ADR-010](ADR-010-backend-realtime.md), [ADR-011](ADR-011-backend-worker.md), [ADR-012](ADR-012-stack-backoffice.md), [ADR-015](ADR-015-posthog.md), [ADR-017](ADR-017-modele-de-donnees.md), [ADR-018](ADR-018-docker-deploiement-vps.md)

## Contexte

Le développement se fait avec un assistant IA (Claude Code). Sans accès aux outils du projet, l'assistant travaille de mémoire : documentation parfois dépassée, composants recopiés à la main, erreurs de build iOS devinées, schéma de base supposé. Des serveurs **MCP** (Model Context Protocol) lui donnent un accès direct et à jour à ces outils.

## Décision

**L'assistant utilise toujours le serveur MCP adapté quand il existe**, plutôt que de travailler de mémoire ou de reproduire à la main ce que l'outil fait.

### Serveurs retenus

| Serveur | Usage obligatoire | ADR concernés | Portée | État |
|---|---|---|---|---|
| **Context7** | Toute question sur une bibliothèque, un framework ou un SDK (NestJS, Drizzle, BullMQ, Better Auth, Next.js, TanStack Query, GRDB, Mapbox…) : consulter la documentation à jour avant d'écrire le code | Tous | Locale | Actif |
| **shadcn** | Rechercher, consulter et **ajouter** tout composant shadcn dans `packages/ui` ; jamais de copie manuelle | ADR-012 | **Projet** (`.mcp.json`, versionné) | Actif |
| **MobileBuildMCP** (ex-XcodeBuildMCP) | Compiler, tester et lancer l'app iOS sur simulateur, lire les erreurs de build, captures d'écran ; préféré aux commandes `xcodebuild` | ADR-006, ADR-007 | Locale | Actif |
| **Postgres MCP Pro** | Lire le schéma, exécuter des requêtes de lecture, analyser les plans d'exécution et les index (dont PostGIS), **en lecture seule** (`--access-mode=restricted`) | ADR-017 | Locale | En attente de la base de développement (`docker-compose.dev.yml`) |
| **Redis** | Inspecter les files BullMQ, les clés et le Pub/Sub pendant le débogage du worker et du temps réel | ADR-010, ADR-011 | Locale | Actif (utile une fois le Redis de développement lancé) |
| **Mapbox** (hébergé) | Géocodage, itinéraires, cartes statiques, documentation Mapbox | ADR-006, ADR-012 | Locale | **À authentifier** (`/mcp` → mapbox) |
| **PostHog** (hébergé) | Créer et lire les feature flags et expériences, interroger les événements | ADR-015, ADR-016 | Locale | **À authentifier** (`/mcp` → posthog) |

Outils complémentaires déjà disponibles : **Figma** (maquettes), **Claude in Chrome** (tests manuels du backoffice).

Le déploiement Docker ne passe pas par un MCP mais par le **skill et l'agent `deploy-vps`** (ADR-018).

### Règles

1. **Toujours** passer par le MCP adapté quand il couvre le besoin (documentation, composants, build iOS, base, Redis, analytics, cartes).
2. **Jamais de secret dans `.mcp.json`**, qui est versionné. Seuls les serveurs sans secret y figurent (shadcn). Les autres sont configurés en portée **locale** (`~/.claude.json`) ou **utilisateur**.
3. **Postgres et Redis uniquement sur l'environnement de développement local**. Jamais d'identifiants de production du VPS dans un MCP.
4. Postgres toujours en **lecture seule** (`--access-mode=restricted`) ; les modifications de schéma passent par les migrations Drizzle.
5. Les clés d'API éventuelles passent par des **variables d'environnement** (`-e`), jamais en argument de commande (elles s'afficheraient en clair dans `claude mcp list`).
6. Un nouveau serveur MCP s'ajoute à ce tableau (mise à jour de cet ADR).

### Actions en attente

- [ ] **Mapbox** : authentifier le serveur (`/mcp` → mapbox, connexion au compte Mapbox).
- [ ] **PostHog** : authentifier le serveur (`/mcp` → posthog, connexion au compte PostHog EU).
- [ ] **Postgres** : aligner l'adresse `postgresql://strava:strava@localhost:5432/strava` sur les identifiants du `docker-compose.dev.yml`.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Pas de MCP, l'assistant travaille de mémoire | Documentation dépassée, erreurs d'API, composants recopiés à la main |
| Tous les serveurs dans `.mcp.json` versionné | Exposerait des identifiants (base, clés d'API) dans le dépôt |
| Postgres en mode lecture-écriture | Risque de modification de la base hors migrations |

## Conséquences

### Positives
- Code écrit à partir de la documentation à jour et de l'état réel du projet.
- Composants shadcn toujours ajoutés au bon endroit, dans la bonne version.
- Boucle de développement iOS plus rapide (build, test, captures depuis l'assistant).

### Négatives / risques
- Dépendance à des serveurs tiers (hébergés ou téléchargés à la volée) ; en cas de panne, retour au travail sans MCP.
- Configuration locale par développeur (hors dépôt) : à refaire sur chaque machine, en suivant cet ADR.
- Serveurs téléchargés via `npx` / `uvx` en `latest` : une nouvelle version peut changer de comportement.

## Références
- Model Context Protocol : https://modelcontextprotocol.io
- Context7 : https://github.com/upstash/context7
- shadcn MCP : https://ui.shadcn.com/docs/mcp
- MobileBuildMCP : https://github.com/getsentry/XcodeBuildMCP
- Postgres MCP Pro : https://github.com/crystaldba/postgres-mcp
- Redis MCP : https://github.com/redis/mcp-redis
- Mapbox MCP : https://github.com/mapbox/mcp-server
- PostHog MCP : https://posthog.com/docs/model-context-protocol
