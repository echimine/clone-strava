# ADR-018 : Dockerisation et déploiement sur le VPS

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : pattern de déploiement maison echimine (GHCR → webhook → VPS), skill `deploy-vps`
- **En lien avec** : [ADR-001](ADR-001-architecture-globale.md), [ADR-003](ADR-003-backend.md), [ADR-005](ADR-005-monorepo.md), [ADR-009](ADR-009-backend-api.md), [ADR-010](ADR-010-backend-realtime.md), [ADR-011](ADR-011-backend-worker.md), [ADR-013](ADR-013-architecture-backoffice.md), [ADR-017](ADR-017-modele-de-donnees.md)

## Contexte

Toutes les apps serveur du monorepo doivent tourner en conteneurs Docker sur le **VPS OVH GRA-01**, qui héberge déjà d'autres apps derrière Traefik avec un pattern de déploiement établi : images construites par GitHub Actions, poussées sur GHCR, puis tirées par le VPS sur appel d'un webhook.

Particularités de ce projet par rapport aux apps existantes :
- **4 images applicatives** (`api`, `realtime`, `worker`, `admin`) dans un **monorepo pnpm + Turborepo** avec des packages internes ;
- **PostGIS** et **Redis** (files BullMQ, Pub/Sub) ;
- des **connexions WebSocket longues** (`realtime`) ;
- un **worker sans serveur HTTP** ;
- `apps/mobile` (projet Xcode) est **hors Docker**.

## Décision

### 1. Pattern de déploiement

```
push main ─► GitHub Actions (matrix 4 apps) ─► build ─► ghcr.io/echimine/strava-<app>:<sha> + :latest
                                                            │
                     webhook (derrière Traefik, en-tête X-Deploy-Token) ─► hook deploy-strava
                                                            │
                     VPS : /opt/www/strava.echimine.fr/prod ─► docker compose pull && up -d
                                                            │
                     attente « healthy » de tous les services ─► notification Discord
```

- **Registry** : GHCR privé, images `ghcr.io/echimine/strava-{api,realtime,worker,admin}`, tags **SHA du commit** et `latest`. Push avec le `GITHUB_TOKEN` éphémère.
- **Déclenchement** : webhook, pas de SSH depuis GitHub. Token **propre à cette app** (`DEPLOY_WEBHOOK_SECRET`).
- **VPS** : login GHCR en lecture seule, un seul environnement **`prod`** dans `/opt/www/strava.echimine.fr/prod/` (`docker-compose.yml`, `.env` en `chmod 600`).
- **Rollback** : fixer les 4 images sur un SHA précédent.

### 2. Domaines

| Service | Domaine | Exposé |
|---|---|---|
| `api` | `api.strava.echimine.fr` | Oui (Traefik, HTTPS) |
| `realtime` | `ws.strava.echimine.fr` (`wss://…/ws`) | Oui (Traefik, WebSocket) |
| `admin` | `admin.strava.echimine.fr` | Oui (Traefik, HTTPS) |
| `worker` | — | **Non** : pas de serveur HTTP, rien à exposer |
| `db`, `redis` | — | **Non** : réseaux internes uniquement |

### 3. Images Docker

**Apps NestJS (`api`, `realtime`, `worker`)** : Dockerfile multi-étapes.

| Étape | Rôle |
|---|---|
| `pruner` | `turbo prune <app> --docker` : ne garde que l'app, ses packages internes et un lockfile élagué |
| `builder` | `pnpm install --frozen-lockfile`, puis build via Turborepo, **dans la même étape** ; puis `pnpm deploy --prod` produit un `node_modules` autonome sans dépendances de dev |
| `runner` | `node:24-alpine`, utilisateur **`node` (non root)**, copie du résultat de `pnpm deploy` uniquement |

- **pnpm à version fixe** (`pnpm@11.25.0`, celle du `packageManager`), installé explicitement.
- **Processus principal = `node`** (`CMD ["node", "dist/main.js"]`), jamais `pnpm start` qui ne relaie pas `SIGTERM`.
- Si un module natif pose problème sous Alpine (musl), passage à `node:24-bookworm-slim`.

**Admin (Next.js)** : sortie **`standalone`**, `outputFileTracingRoot` à la racine du monorepo, `transpilePackages: ['@repo/ui']`, `HOSTNAME=0.0.0.0`, utilisateur non root.

**Packages internes** : `core`, `db`, `contracts` et `realtime` sont **compilés** (`dist/`), car les décorateurs NestJS ne s'exécutent pas depuis le source. `packages/db` embarque aussi le dossier des migrations. `packages/ui` reste en source (consommé uniquement par l'admin).

### 4. Migrations

- Exécutées **au démarrage de l'api** : l'entrypoint lance `migrate()` (Drizzle, compilé dans `packages/db`), puis `exec node dist/main.js`.
- Le `worker` et l'`admin` attendent que l'api soit « healthy », donc que les migrations soient passées.
- L'api reste à **une seule instance**. Si elle doit passer à plusieurs, les migrations deviendront un service ponctuel dédié.

### 5. Services, réseaux et volumes

| Service | Image | Réseaux | Volume |
|---|---|---|---|
| `db` | `postgis/postgis:17-3.5` (version épinglée) | `data` | `db-data` |
| `redis` | `redis:7-alpine` | `data` | `redis-data` |
| `api` | `strava-api` | `traefik-public`, `data`, `admin-api` | — |
| `realtime` | `strava-realtime` | `traefik-public`, `data` | — |
| `worker` | `strava-worker` | `data`, `egress` | — |
| `admin` | `strava-admin` | `traefik-public`, `admin-api` | — |

| Réseau | Type | Rôle |
|---|---|---|
| `traefik-public` | Externe, partagé entre les apps du VPS | Exposition HTTPS via Traefik |
| `data` | Interne (sans Internet) | Accès à PostgreSQL et Redis |
| `admin-api` | Interne | Proxy de l'admin vers l'api (`http://api:3001`), sans passer par le réseau partagé |
| `egress` | Bridge standard, sans exposition | Sortie Internet du worker (bucket OVH, RevenueCat, PostHog) |

Règles pour tous les services :
- **aucun `ports:` publié** ; exposition uniquement via les labels Traefik ;
- `security_opt: no-new-privileges:true` ;
- `restart: unless-stopped` ;
- variables d'environnement **déclarées par service** (chacun ne reçoit que ce dont il a besoin), valeurs dans le `.env` du VPS uniquement ;
- noms de routeurs Traefik préfixés `strava-` (uniques sur le VPS) ;
- `container_name` uniquement sur `db` (utilisé par le script de backup) ; **jamais sur `realtime` ni `worker`**, pour pouvoir lancer plusieurs instances ;
- rotation des logs Docker configurée (`max-size`, `max-file`) : les logs Pino sont volumineux.

**Redis** : `--appendonly yes --appendfsync everysec --maxmemory-policy noeviction` (obligatoire pour BullMQ), mot de passe via un fichier de configuration monté (pas en argument de commande, visible dans `docker inspect`).

### 6. Santé et arrêt propre

| Service | Healthcheck | `stop_grace_period` |
|---|---|---|
| `api` | `GET /health` (base + Redis), route publique hors `/v1`, hors limitation de débit et hors authentification | 15 s |
| `realtime` | `GET /health` | 15 s (ferme les connexions en `4009`) |
| `worker` | **fichier heartbeat** `/tmp/worker-alive` mis à jour toutes les 15 s tant que Redis et les workers BullMQ sont prêts | 120 s (termine les jobs en cours), à ajuster selon la durée maximale d'un job |
| `admin` | `GET /login`, code < 500 | 10 s |
| `db` | `pg_isready` | 30 s |
| `redis` | `redis-cli ping` | 30 s |

- `init: true` sur les services Node, pour relayer correctement les signaux.
- NestJS : `enableShutdownHooks()` ; le realtime ferme ses connexions en `4009`, le worker attend la fin de ses jobs (`worker.close()`).

### 7. Backups

- **PostgreSQL** : script générique existant `/opt/backups/backup-db.sh`, branché par un service et un timer systemd `backup-strava-db` (chaque nuit), vers le bucket de backups (rétention 30 jours). **Restauration testée** dans une base jetable (vérifier l'extension `postgis`, les tables géométriques et les index GiST).
- **Redis : pas de backup externe.** Il ne contient que des files et des événements transitoires ; la vérité est dans PostgreSQL. L'AOF protège contre un redémarrage. En cas de perte du volume, un **job de réconciliation** remet en file les activités restées `pending` ou `processing` trop longtemps (index partiel prévu dans ADR-017).
- **Bucket d'assets** (traces, médias) : créé avec **un utilisateur S3 propre à l'app**, jamais avec l'utilisateur de backup, avec une policy limitée à ce bucket.

### 8. Développement local

- `docker-compose.dev.yml` avec **uniquement `db` et `redis`**, mêmes images et options qu'en production, ports liés à `127.0.0.1`.
- Les apps tournent sur la machine avec `pnpm dev` (rechargement à chaud).
- Profil optionnel `apps` pour construire et lancer les 4 images localement avant un push.
- Un `.env.example` par app (noms des variables uniquement).

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Déploiement par SSH depuis GitHub Actions | Clé SSH à privilégier côté GitHub ; le webhook est le pattern déjà en place |
| Build des images sur le VPS | Consomme les ressources du serveur de production, pas de cache de build partagé |
| Une seule image pour les 3 apps NestJS | Images plus lourdes, déploiements et dimensionnement liés ; contraire à ADR-003 |
| WebSocket sur `api.strava…/ws` (routage par chemin) | Règle Traefik plus fragile ; le sous-domaine dédié isole le trafic WebSocket |
| Environnement `staging` sur le VPS | Double les conteneurs ; les tests passent par le compose local |
| Kubernetes / orchestrateur | Disproportionné pour un VPS unique |
| Backup externe de Redis | Données transitoires ; la réconciliation depuis PostgreSQL suffit |

## Conséquences

### Positives
- Même pattern que les autres apps du VPS : outillage, webhook, Traefik et backups réutilisés.
- Images légères et reproductibles grâce à `turbo prune` et `pnpm deploy`.
- Aucun service exposé en direct ; base et Redis inaccessibles depuis Internet.
- Chaque app se déploie et se dimensionne indépendamment.

### Négatives / risques
- **TypeScript 7 et NestJS** : la CLI Nest s'appuie sur l'API du compilateur TypeScript, absente de TS 7. À vérifier au démarrage du projet ; solution probable : build **SWC** pour les apps et packages NestJS, ou TypeScript 5.x pour ceux-ci.
- **`turbo prune` avec pnpm 11** : compatibilité du lockfile à vérifier ; scripts de build des dépendances natives (`msgpackr-extract`, `sharp`, `@swc/core`) à autoriser explicitement dans pnpm.
- **Proxy Next.js** : les destinations des réécritures sont figées au build ; la cible `http://api:3001` est fixe via le réseau `admin-api`.
- **`trust proxy`** : à activer dans Express, sinon la limitation de débit voit tous les clients avec l'IP de Traefik.
- **Timeout WebSocket** de Traefik (60 s par défaut en lecture) : à tester ; une modification impacterait la configuration Traefik partagée par toutes les apps.
- **Chaque déploiement coupe les connexions WebSocket** (`4009`) : le mobile se reconnecte (ADR-008).
- **Durée de déploiement** : 4 images, migrations et arrêt du worker doivent tenir dans le délai du script de déploiement (300 s).
- **Apple Silicon** : vérifier la disponibilité `arm64` de l'image PostGIS pour le développement local.

## Mise en œuvre

### Outillage obligatoire : skill et agent `deploy-vps`

Toute la mise en œuvre de cet ADR (Dockerfiles, `.dockerignore`, `deploy.yml`, compose, webhook, backups, étapes côté VPS) **se fait avec le skill `deploy-vps` et l'agent `deploy-vps`**, qui portent le pattern maison et ses pièges connus :

| Outil | Rôle | Quand l'utiliser |
|---|---|---|
| **Skill `deploy-vps`** (`/deploy-vps`) | Charge le pattern GHCR → webhook → VPS, les règles non négociables, les templates (`Dockerfile.nextjs-standalone`, `Dockerfile.node-migrations-entrypoint`, `docker-compose.yml`, `deploy.yml`, `hooks.json`, `deploy.sh`, `.dockerignore`) et la checklist | En premier, avant toute création ou modification de fichier de déploiement |
| **Agent `deploy-vps`** | Inspecte le repo, génère les fichiers à partir des templates en les adaptant au monorepo, et liste les fichiers et étapes à faire côté VPS ; ne touche jamais aux secrets | Pour générer ou faire évoluer les fichiers Docker et CI/CD, et pour chaque nouvelle app ou nouveau service à déployer |

Règles :
- **Ne pas écrire à la main** un Dockerfile, un compose ou un workflow de déploiement sans passer par le skill et l'agent : les templates et pièges connus (pin du gestionnaire de paquets, healthcheck sur route protégée, webhook, backups) y sont déjà intégrés.
- Les **templates et la documentation de référence** vivent dans le dépôt de documentation echimine (`echimine-doc`) : fiches `vps/`, ADR `0001` et `0002`, templates du skill.
- Les écarts propres à ce projet décrits ci-dessus (pnpm et `turbo prune`, PostGIS, Redis, WebSocket, worker sans HTTP, réseaux `admin-api` et `egress`) sont donnés à l'agent comme contexte, avec cet ADR.
- Après le premier déploiement, l'agent met à jour la documentation echimine (fiche de déploiement de l'app, sur le modèle des apps existantes).

### Fichiers et étapes

**Dans le repo** (après validation) : 4 Dockerfiles, `.dockerignore` (exclut `apps/mobile`, `node_modules`, `.next`, `dist`, `.turbo`, `.git`, `.env*`, `docs`), `.github/workflows/deploy.yml` (matrix 4 apps), `docker-compose.dev.yml`, configuration Next.js de l'admin, sorties `dist/**` dans `turbo.json`, script de migration dans `packages/db`, heartbeat du worker, hooks d'arrêt NestJS, `pnpm-lock.yaml` commité à jour.

**Secrets GitHub** : `DEPLOY_WEBHOOK_SECRET` ; `NEXT_PUBLIC_MAPBOX_TOKEN` (jeton public restreint) en variable. Aucun secret applicatif dans GitHub.

**DNS OVH** : `api.strava`, `ws.strava`, `admin.strava` vers l'IP du VPS.

**Sur le VPS** :
- dossier `/opt/www/strava.echimine.fr/prod/` avec `docker-compose.yml`, `.env` (600), configuration Redis ;
- accès GHCR en lecture seule aux 4 images ;
- hook `deploy-strava` (token dédié), script de déploiement (`EXPECTED_SERVICES="db redis api worker realtime admin"`), montage du dossier dans le conteneur webhook ;
- premier déploiement : tous les services « healthy », `/health` en HTTPS, connexion WebSocket de plus de 2 minutes, connexion au backoffice, extension `postgis` présente ;
- rollback testé ;
- bucket d'assets avec utilisateur dédié ;
- backup PostgreSQL branché et restauration testée ;
- fiche de déploiement ajoutée à la documentation echimine.

## Références
- Documentation echimine : ADR `0001-deploiement-ghcr-webhook-vps`, `0002-backups-buckets-separes` ; fiches `procedure-cicd-nextjs-ghcr.md`, `vps-ovh-gra-01-backups.md`, `vps-ovh-gra-01-traefik.md`
- Turborepo et Docker : https://turborepo.com/docs/guides/tools/docker
- pnpm deploy : https://pnpm.io/cli/deploy
- Next.js standalone : https://nextjs.org/docs/app/api-reference/config/next-config-js/output
- Image PostGIS : https://hub.docker.com/r/postgis/postgis
