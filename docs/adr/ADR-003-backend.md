# ADR-003 : Stack et architecture du backend

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : dossier d'architecture Like-Strava, slides 03 « Stack · backend », 04 « Architecture backend · monolithe modulaire », 07 « Monorepo », 08 « Architecture globale »
- **Dépend de** : [ADR-001](ADR-001-architecture-globale.md)
- **En lien avec** : [ADR-005](ADR-005-monorepo.md)

## Contexte

Le backend porte les règles métier et protège les données (ADR-001). Il est composé de trois rôles :
- **api** : endpoints REST pour le mobile et le backoffice ;
- **realtime** : serveur WebSocket qui pousse les événements au mobile ;
- **worker** : exécution des jobs lourds.

L'objectif est que **l'API n'exécute jamais de job** : elle se contente de les mettre en file. Or le worker contient du vrai métier (slide 10 : lecture de l'activité, du profil et du type de sport, calcul des métriques, construction du tracé, zone de confidentialité, écriture des statistiques). L'API et le worker ont donc besoin des **mêmes règles métier, du même schéma de base et des mêmes contrats**.

## Décision

### Stack

| Brique | Choix | Rôle |
|---|---|---|
| Framework | **NestJS** | Les trois apps : api, realtime, worker |
| Base de données | **PostgreSQL + PostGIS** | Données relationnelles et géospatiales |
| Accès aux données | **Drizzle ORM** | Schéma typé, requêtes, migrations |
| Messagerie | **Redis** | Pub/Sub entre worker, api et realtime |
| Tâches asynchrones | **BullMQ** (sur Redis) | Files et jobs, retries, backoff |
| Stockage objet | **Bucket OVH Object Storage** (compatible S3) | Traces brutes et médias, URLs pré-signées |
| Authentification | **Better Auth** | Comptes, sessions, OAuth ; jeton porteur pour iOS |

### Trois apps NestJS, un métier partagé

```
apps/
├── api/        controllers REST + Better Auth → met les jobs en file, ne les exécute jamais
├── realtime/   gateways WebSocket → s'abonne à Redis, vérifie la session, pousse au mobile
└── worker/     processors BullMQ → exécute les jobs en appelant le métier partagé
packages/
├── db/         schéma Drizzle, client, migrations
├── core/       modules métier Nest : service + use cases + repository (sans controller)
└── contracts/  schémas Zod : DTO de l'API, données des jobs, événements temps réel
```

- Chaque app **ne contient que ses points d'entrée** (controllers, gateways ou processors) et importe les modules métier de `packages/core`.
- Les trois apps se **déploient et se dimensionnent séparément**.
- Les **contrats partagés** (`packages/contracts`) garantissent que l'API et le worker s'accordent sur le format des jobs, et que le worker et le serveur WS s'accordent sur le format des événements.

### Monolithe modulaire

Le métier est découpé en **un module par domaine** (activities, users, social, segments, auth…). Chaque module expose un **service** et possède ses tables. Flux d'une requête ou d'un job :

```
Controller (api) / Processor (worker) → Service → Use case → Repository → PostgreSQL
```

Un module n'appelle un autre module que par son service exporté. Les réactions entre domaines passent de préférence par des jobs ou des événements. Le détail des règles de frontière sera précisé dans un ADR dédié.

## Alternatives envisagées

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **Chaque app écrit son propre métier**, seuls le schéma et les contrats sont partagés | Apps indépendantes | Règles dupliquées qui divergent (ex. calcul de distance différent entre api et worker) | Rejeté |
| **Worker et realtime appellent l'API en HTTP** | Aucun code partagé | Le worker recharge l'API à chaque job, ce qu'on cherche justement à éviter | Rejeté |
| **Une seule app NestJS avec 3 points d'entrée** | Le plus simple, processus quand même séparés | Pas de séparation claire des apps dans le monorepo | Rejeté |
| **Microservices par domaine** | Indépendance totale | Coût opérationnel, transactions distribuées | Rejeté |
| **Packages internes partagés** (`core`, `db`, `contracts`) | Une seule version des règles, apps séparées | Configuration de compilation des packages Nest | **Retenu** |

Autres choix de stack écartés : Express/Fastify seul (pas de structure modulaire), MongoDB (géospatial et relationnel moins riches), Prisma (support PostGIS limité), Auth0/Clerk (dépendance SaaS, données hors de notre base), stockage disque sur le VPS.

## Conséquences

### Positives
- L'API reste légère et rapide ; les calculs lourds tournent dans le worker.
- Une seule implémentation des règles métier, utilisée par l'API et le worker.
- Tout le backend est en TypeScript : types partagés avec le backoffice.
- PostGIS couvre nativement les besoins géospatiaux (tracés, segments, recherche par zone).

### Négatives / risques
- **Compilation des packages internes** : `packages/core` utilise les décorateurs NestJS, il faut une configuration TypeScript et Turborepo adaptée (packages compilés, ordre de build).
- **Frontières non imposées par le compilateur** : prévoir des règles ESLint (`eslint-plugin-boundaries`) pour interdire les imports internes entre modules.
- **PostGIS avec Drizzle** : types géométriques personnalisés et SQL brut pour les requêtes spatiales, index GiST dans les migrations.
- **Better Auth** : pas d'intégration NestJS officielle ni de SDK iOS. À câbler dans l'api (et vérification de session dans realtime) ; jetons gérés côté Swift (Keychain).
- **Redis critique** (voir ADR-001).

## Références
- Dossier d'architecture Like-Strava, slides 03, 04, 07, 08
- [ADR-001 : Architecture globale](ADR-001-architecture-globale.md)
- [ADR-005 : Monorepo](ADR-005-monorepo.md)
- NestJS : https://docs.nestjs.com
- Drizzle ORM : https://orm.drizzle.team
- BullMQ : https://docs.bullmq.io
- Better Auth : https://www.better-auth.com
