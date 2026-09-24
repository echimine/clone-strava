# ADR-010 : Backend · app `realtime` (passerelle WebSocket)

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Détaille** : [ADR-003](ADR-003-backend.md)
- **Amende** : [ADR-005](ADR-005-monorepo.md) (ajout de `packages/realtime`)
- **En lien avec** : [ADR-001](ADR-001-architecture-globale.md), [ADR-006](ADR-006-stack-mobile.md), [ADR-008](ADR-008-mobile-offline-sync.md), [ADR-009](ADR-009-backend-api.md), [ADR-011](ADR-011-backend-worker.md)

## Contexte

Le serveur `realtime` prévient le mobile quand quelque chose change côté serveur (ex. une activité traitée par le worker, ADR-001). Contraintes :
- le mobile utilise le **WebSocket natif** `URLSessionWebSocketTask` (ADR-006) : protocole WebSocket standard, sans surcouche ;
- le mobile fonctionne déjà en **resynchronisant par l'API** à chaque retour au premier plan et à chaque reconnexion (ADR-008) : le temps réel est un confort, pas la source de vérité ;
- le service doit pouvoir tourner en **plusieurs instances** et être redéployé sans impact sur l'API.

## Décision

### 1. Une passerelle qui ne fait que du transport

`apps/realtime` **authentifie, garde les connexions et route des événements par topic**. Elle ne contient aucune règle métier, **n'accède pas à la base** et n'appelle pas l'API. Toute la logique reste dans l'API et le worker.

### 2. Stack

| Brique | Choix |
|---|---|
| Framework | **NestJS** (HTTP uniquement pour `/health`) |
| WebSocket | bibliothèque **`ws`**, `WebSocketServer({ noServer: true })` branché sur l'événement `upgrade` du serveur HTTP de Nest, chemin **`/ws`** |
| Jetons | JWT **HS256** (`jsonwebtoken`), vérifiés localement |
| Redis | `ioredis`, connexion dédiée en mode abonné |
| Protocole | `packages/realtime` (schémas Zod, voir §8) |
| Socle | Pino, configuration validée par Zod (ADR-009) |

On n'utilise pas l'adaptateur `@nestjs/platform-ws` : gérer l'`upgrade` soi-même permet de **refuser un jeton invalide par un `401` avant d'ouvrir la connexion WebSocket**.

### 3. Authentification par jeton court

1. Le mobile demande un jeton à l'API : `POST /v1/realtime/token`, authentifié par sa session Better Auth (ADR-009).
2. L'API renvoie un JWT signé avec `REALTIME_TOKEN_SECRET`, valable **60 secondes**, contenant : l'utilisateur (`sub`), les **topics autorisés**, l'émetteur (`iss: clone-strava-api`) et le destinataire (`aud: clone-strava-realtime`).
3. Le mobile ouvre `wss://…/ws` avec `Authorization: Bearer <jeton>`.
4. La passerelle vérifie **localement** la signature, l'algorithme, l'émetteur, le destinataire et l'expiration. Aucun appel réseau. Jeton invalide = `401` et connexion refusée.
5. Le jeton ne sert qu'à l'ouverture : la connexion reste valide après son expiration. **Chaque reconnexion demande un nouveau jeton.** Une session révoquée ne peut donc plus se reconnecter au-delà de 60 secondes.

Toute connexion qui présente un en-tête `Origin` (navigateur) est refusée : le backoffice n'utilise pas le temps réel (ADR-001).

### 4. Topics et abonnement explicite

- Le client s'abonne après la connexion : `{ "a": "sub", "topic": "user:123" }`.
- La passerelle n'accepte que les topics **présents dans le jeton** ; sinon elle répond `sub:err` (`forbidden`).
- Topics du MVP :

| Topic | Destinataire | Exemples d'événements |
|---|---|---|
| `user:{userId}` | L'utilisateur lui-même, sur tous ses appareils | `activity.processed`, `activity.failed` |

- Plus tard, d'autres topics pourront s'ajouter (ex. `activity:{id}` pour les commentaires en direct) sans changer l'architecture.

### 5. Protocole (versionné)

**Événement, serveur → client :**

```json
{ "v": 1, "t": "activity.processed", "id": "evt_…", "data": { "activityId": "…", "status": "processed", "at": "2026-09-24T10:00:00Z" } }
```

- `v` : version du protocole ; un client qui reçoit une version inconnue ignore le message.
- `t` : type d'événement, au format `{ressource}.{verbe}`.
- `id` : identifiant unique, pour ignorer un doublon côté client.
- `data` : **contenu minimal**. On n'envoie jamais les données de la ressource : le client recharge par l'API (`GET /v1/activities/:id`). L'API reste l'unique source de vérité, et c'est le même code que la resynchronisation (ADR-008).

**Contrôle :**

| Sens | Messages |
|---|---|
| Client → serveur | `{a:"sub", topic}`, `{a:"unsub", topic}`, `{a:"ping"}` |
| Serveur → client | `{a:"sub:ok", topic}`, `{a:"sub:err", topic, reason: "forbidden" \| "limit"}`, `{a:"pong"}` |

**Codes de fermeture :**

| Code | Signification | Réaction du client |
|---|---|---|
| `4001` | Jeton invalide ou expiré détecté après l'ouverture | Nouveau jeton, puis reconnexion |
| `4008` | Quota de messages dépassé | Reconnexion avec backoff |
| `4009` | Arrêt du serveur (déploiement) | Reconnexion immédiate |

Un message illisible ou inconnu est **ignoré** (jamais d'exception), mais compté dans le quota.

### 6. Diffusion via Redis

- Un **canal unique** : `realtime:events`.
- L'API ou le worker publie `{ "topics": ["user:123"], "envelope": { … } }`. **Les topics sont calculés par l'émetteur** : la passerelle n'a rien à décider.
- Chaque instance de la passerelle est abonnée au canal et envoie l'enveloppe aux connexions locales abonnées à ces topics (registre en mémoire `topic → connexions`).
- Plusieurs instances possibles, sans sessions collantes.
- La source d'événements est derrière une interface : remplaçable par un faux en test.

### 7. Livraison : au plus une fois

- Pas de file persistée, pas de rattrapage : un événement émis pendant que le mobile est déconnecté est perdu.
- C'est assumé : à chaque connexion ou reconnexion, le mobile recharge l'état par l'API (ADR-008).

### 8. Package partagé `packages/realtime`

Sans dépendance à NestJS, utilisé par `api`, `worker` et `realtime` :
- schémas Zod de l'enveloppe, des messages de contrôle et du message publié sur Redis ;
- codes de fermeture, nom du canal Redis, version du protocole ;
- fonctions de nommage des topics (`userTopic(userId)`) ;
- registre des connexions par topic (utilisé par `realtime`) ;
- un **publieur** (`publishRealtimeEvent(topics, type, data)`) utilisé par l'API et le worker, qui construit l'enveloppe (avec `id` et `v`) et publie sur Redis.

Ce package s'ajoute à ceux listés dans ADR-005.

### 9. Protections et robustesse

- **Quotas par connexion** : nombre maximal de topics, nombre maximal de messages sur une fenêtre de temps (dépassement → fermeture `4008`), taille maximale d'un message (`maxPayload`).
- **Heartbeat** : le client envoie un `ping` applicatif toutes les **25 secondes** ; le serveur ferme les connexions silencieuses.
- **Arrêt propre** : au `SIGTERM`, toutes les connexions sont fermées en `4009` avant l'arrêt (hooks d'arrêt de Nest).
- **Santé** : `GET /health` (Redis joignable, nombre de connexions).
- **Reverse proxy** du VPS configuré pour l'`upgrade` WebSocket et des timeouts longs.

### 10. Tests

- Unitaires : encodage/décodage des messages, vérification des jetons, quotas.
- Intégration : ouverture avec jeton valide et invalide, refus d'un topic non autorisé, diffusion d'un événement vers **deux instances** via Redis, fermeture `4009` à l'arrêt.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Socket.IO | Protocole propriétaire, incompatible avec le WebSocket natif iOS |
| Adaptateur `@nestjs/platform-ws` | Moins de contrôle sur l'ouverture de connexion (refus avant `upgrade`) |
| Vérifier la session Better Auth à chaque connexion (lecture en base ou appel à l'API) | Couplage à l'API ou à la base, latence à chaque connexion ; le jeton court évite les deux |
| Envoyer les valeurs officielles dans l'événement | Deux sources de données pour le mobile ; le rechargement par l'API garde un seul chemin |
| Abonnement automatique à la connexion | Moins évolutif : l'abonnement explicite permet d'ajouter des topics sans changer le protocole |
| Redis Streams avec rattrapage des événements manqués | Inutile tant que le mobile resynchronise par l'API |
| Service managé (Pusher, Ably) | Dépendance SaaS et coût, pour un besoin simple |

## Conséquences

### Positives
- Compatible directement avec `URLSessionWebSocketTask`, sans dépendance côté iOS.
- Passerelle sans base ni métier : simple, testable, facile à multiplier.
- Aucune requête réseau pour authentifier une connexion.
- Ajouter un type d'événement ou un topic ne demande aucun changement d'architecture.

### Négatives / risques
- **Plomberie à écrire** : registre, quotas, heartbeat, fermeture propre.
- **Secret partagé** `REALTIME_TOKEN_SECRET` entre `api` et `realtime` : à stocker comme secret, à faire tourner si compromis.
- **Événements perdus** si le mobile est déconnecté (accepté, ADR-008).
- **Une requête de plus** à chaque connexion (jeton, puis rechargement de l'activité) : négligeable.

### Pour plus tard
- **Présence** : marqueur Redis « utilisateur connecté » posé par la passerelle, pour que le worker choisisse entre WebSocket et notification APNs (ADR-006, ADR-011).

## Références
- [ADR-006 : Stack détaillée du mobile](ADR-006-stack-mobile.md)
- [ADR-008 : Hors ligne et synchronisation du mobile](ADR-008-mobile-offline-sync.md)
- [ADR-009 : Backend · app api](ADR-009-backend-api.md)
- ws : https://github.com/websockets/ws
- RFC 6455 (WebSocket) : https://www.rfc-editor.org/rfc/rfc6455
