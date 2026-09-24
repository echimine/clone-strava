# ADR-009 : Backend · app `api` (REST)

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Détaille** : [ADR-003](ADR-003-backend.md) (stack et architecture du backend)
- **En lien avec** : [ADR-001](ADR-001-architecture-globale.md), [ADR-005](ADR-005-monorepo.md), [ADR-010](ADR-010-backend-realtime.md), [ADR-011](ADR-011-backend-worker.md), [ADR-014](ADR-014-revenuecat.md), [ADR-015](ADR-015-posthog.md)

## Contexte

ADR-003 découpe le backend en trois apps NestJS (`api`, `realtime`, `worker`) qui partagent le métier via `packages/core`, `packages/db` et `packages/contracts`. Cet ADR fixe :
- le **socle commun** aux trois apps (contrats, validation, logs, configuration), auquel ADR-010 et ADR-011 renvoient ;
- la stack propre à l'app `api` : le seul point d'entrée des clients (mobile et backoffice).

## Décision

### Socle commun aux trois apps backend

| Sujet | Choix |
|---|---|
| Contrats partagés | **Zod**, dans `packages/contracts` : corps et réponses de l'API, données des jobs, événements temps réel |
| Validation dans Nest | Pipe de validation Zod (ex. `nestjs-zod`) : les DTO sont dérivés des schémas de `contracts`, sans class-validator |
| Configuration | Variables d'environnement **validées par un schéma Zod au démarrage** : l'app refuse de démarrer si une variable manque |
| Logs | **Pino** via `nestjs-pino` : logs JSON structurés sur la sortie standard |
| Accès aux données | Drizzle, schéma dans `packages/db` (ADR-003) |

**Logs, en pratique :**
- Chaque ligne de log est un objet JSON (niveau, message, contexte, identifiants). Sur le VPS, Docker récupère la sortie standard ; on peut ensuite brancher un outil de consultation sans toucher au code.
- Chaque requête HTTP reçoit un **identifiant de corrélation** (`requestId`). Il est recopié dans les données des jobs et dans les événements publiés, pour suivre une activité de l'API au worker puis au serveur WS.
- Les jetons, mots de passe et en-têtes `Authorization` sont **masqués** automatiquement (`redact`).
- Le suivi des erreurs (ex. Sentry) pourra être ajouté plus tard.

### Stack de l'app `api`

| Brique | Choix | Rôle |
|---|---|---|
| Framework | **NestJS** (adaptateur Express par défaut) | Controllers REST |
| Authentification | **Better Auth** | Comptes, sessions ; jeton porteur pour iOS, cookie pour le backoffice |
| Bucket | **AWS SDK v3** (`@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`) configuré sur l'endpoint **OVH Object Storage** | URLs pré-signées |
| Files de jobs | **BullMQ** (`@nestjs/bullmq`), **producteur uniquement** | Mise en file, jamais d'exécution |
| Redis | client `ioredis` | Publication d'événements temps réel via le publieur de `packages/realtime` (ADR-010) |
| Jetons temps réel | `jsonwebtoken` (HS256, secret `REALTIME_TOKEN_SECRET` partagé avec `realtime`) | Endpoint `POST /v1/realtime/token` |
| Abonnements | Webhook **RevenueCat** (ADR-014) | Endpoint `POST /v1/webhooks/revenuecat` |
| Analytics | `posthog-node`, via le module `analytics` de `packages/core` (ADR-015) | Événements serveur fiables |
| Documentation | **OpenAPI générée depuis les schémas Zod** | Référence de l'API et génération des modèles Swift (ADR-005) |
| Protection | `@nestjs/throttler` (limitation de débit) ; pas de CORS : le backoffice passe par le proxy Next.js (ADR-013) et le mobile n'est pas concerné par le CORS | — |
| Santé | `@nestjs/terminus` | Endpoint `/health` (base, Redis) pour le déploiement |

### Principes

1. **L'API ne fait jamais de traitement lourd** : elle valide, écrit en base, met en file et répond (`202 Accepted` pour les traitements asynchrones).
2. **Les controllers sont minces** : validation Zod, garde d'authentification, appel au service du module (`packages/core`), mise en forme de la réponse.
3. **Authentification** :
   - Better Auth est monté sur `/api/auth/*` ;
   - une garde vérifie la session sur toutes les routes protégées ;
   - une garde de **rôle admin** protège les endpoints du backoffice (ADR-004) ;
   - `GET /v1/me` renvoie l'utilisateur courant et son rôle (utilisé par le backoffice pour afficher ou refuser l'accès, ADR-013).
4. **Jeton temps réel** : `POST /v1/realtime/token`, protégé par la session, renvoie un JWT valable 60 secondes contenant l'utilisateur et ses topics autorisés (`user:{userId}` pour le MVP). Le mobile l'utilise pour ouvrir la connexion WebSocket ; la passerelle le vérifie sans appeler l'API (ADR-010).
5. **Webhook RevenueCat** : `POST /v1/webhooks/revenuecat`, hors session utilisateur, authentifié par un **en-tête secret** configuré dans RevenueCat. L'API vérifie le secret, enregistre l'événement (dédupliqué par son identifiant), met le job `sync-subscription` en file et répond `200` immédiatement (ADR-014).
6. **Bucket privé** : aucune lecture publique. Les URLs pré-signées ont une durée courte, et les clés d'objets suivent une convention, par exemple `activities/{userId}/{activityId}/trace.json.gz`.
7. **Format d'erreur unique** pour toute l'API (code, message, détails de validation), décrit dans `contracts`.
8. **Routes versionnées** (`/v1/...`) pour pouvoir faire évoluer l'API sans casser les anciennes versions de l'app mobile, qui restent installées sur les téléphones tant que l'utilisateur ne met pas à jour. Pour éviter d'avoir à créer une `/v2` :
   - **changements compatibles uniquement** : ajouter un champ est permis ; renommer, supprimer ou changer le type d'un champ ne l'est pas ;
   - **clients tolérants** : l'app ignore les champs inconnus, les nouveaux champs sont optionnels ;
   - **version minimale de l'app** : l'API expose la version minimale acceptée ; en dessous, l'app demande à l'utilisateur de mettre à jour. On peut ainsi retirer une ancienne version de l'API sans attendre indéfiniment.

## Alternatives envisagées

| Sujet | Alternative | Pourquoi écartée |
|---|---|---|
| Validation | class-validator + class-transformer | Doublon avec les schémas Zod des contrats, qui servent déjà au backoffice et au worker |
| Contrats | tRPC / ts-rest | Le mobile Swift ne peut pas en profiter ; REST + OpenAPI reste lisible par tous les clients |
| Logs | Logger intégré de NestJS | Texte non structuré, difficile à filtrer ; pas de corrélation ni de masquage |
| Logs | Winston | Plus lent et plus verbeux à configurer que Pino pour des logs JSON |
| Adaptateur HTTP | Fastify | Plus rapide, mais l'intégration Better Auth + NestJS est plus simple avec Express ; à reconsidérer si les performances l'exigent |
| Bucket | SDK OVH spécifique | L'API S3 standard via AWS SDK v3 évite de dépendre d'OVH |

## Conséquences

### Positives
- Un seul schéma Zod par échange, utilisé pour valider, typer (backoffice) et documenter (OpenAPI → Swift).
- Logs exploitables dès le départ, avec un fil conducteur de l'API jusqu'au WS.
- L'API reste rapide et prévisible : aucun job ne tourne dans son processus.

### Négatives / risques
- **Zod dans NestJS** n'est pas le chemin par défaut : dépendance à une bibliothèque d'intégration (ou pipe maison) et génération OpenAPI à vérifier.
- **Better Auth avec NestJS** : pas d'intégration officielle, à câbler et tester (bearer pour iOS, cookie pour le backoffice).
- **OVH via AWS SDK** : endpoint, région et style d'URL à configurer, et à tester sur les URLs pré-signées.
- **Versionnement** : il faudra maintenir les anciennes versions tant que des apps mobiles non mises à jour les utilisent.

## Références
- [ADR-003 : Stack et architecture du backend](ADR-003-backend.md)
- [ADR-005 : Monorepo](ADR-005-monorepo.md)
- Zod : https://zod.dev
- nestjs-pino : https://github.com/iamolegga/nestjs-pino
- AWS SDK v3 S3 : https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/client/s3/
- OVHcloud Object Storage (S3) : https://help.ovhcloud.com/csm/fr-public-cloud-storage-s3-getting-started
- BullMQ avec NestJS : https://docs.nestjs.com/techniques/queues
