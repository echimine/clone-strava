# ADR-011 : Backend · app `worker` (jobs BullMQ)

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Détaille** : [ADR-003](ADR-003-backend.md)
- **En lien avec** : [ADR-001](ADR-001-architecture-globale.md), [ADR-009](ADR-009-backend-api.md) (socle commun), [ADR-010](ADR-010-backend-realtime.md), [ADR-014](ADR-014-revenuecat.md), [ADR-015](ADR-015-posthog.md)

## Contexte

Le worker exécute les traitements lourds que l'API met en file (ADR-001). Le premier est `process-activity` (slide 10) : lire l'activité, le profil et le type de sport, télécharger la trace brute, nettoyer les points, calculer les métriques, construire le tracé, appliquer la zone de confidentialité, écrire le résultat en transaction, puis publier `activity.processed`.

## Décision

### Stack

| Brique | Choix | Rôle |
|---|---|---|
| Framework | **NestJS** en **contexte applicatif** (pas de serveur HTTP) | Processors BullMQ |
| Files | **BullMQ** (`@nestjs/bullmq`), **consommateur** | Exécution des jobs |
| Bucket | **AWS SDK v3** sur l'endpoint OVH | Lecture des traces brutes |
| Abonnements | API REST **RevenueCat** | État complet d'un abonné (ADR-014) |
| Analytics | `posthog-node`, via le module `analytics` de `packages/core` | Événements serveur (`activity_processed`, `subscription_*`, ADR-015) |
| Base | Drizzle (`packages/db`), PostGIS | Lecture et écriture en transaction |
| Métier | Modules de `packages/core` | Mêmes règles que l'API |
| Redis | `ioredis` | Publication des événements temps réel via le publieur de `packages/realtime` (ADR-010) |
| Socle | Pino, configuration validée par Zod, contrats Zod (ADR-009) | — |

### Jobs

| File | Job | Déclenché par | MVP |
|---|---|---|---|
| `activities` | `process-activity` | `POST /activities/:id/complete` | Oui |
| `segments` | `match-segments` (efforts sur segments) | Fin de `process-activity` | Oui, job séparé (ADR-019) |
| `subscriptions` | `sync-subscription` : lit l'état de l'abonné via l'API REST de RevenueCat, met à jour le statut premium en base, envoie l'événement à PostHog (ADR-014) | Webhook RevenueCat reçu par l'API | Oui, dès que les abonnements existent |
| `media` | génération de la miniature de carte | Fin de `process-activity` | Plus tard |
| `notifications` | envoi APNs | Événements métier | **Plus tard** (pas encore de compte Apple Developer) |

### Principes

1. **Les processors sont minces** : ils valident les données du job avec le schéma Zod de `contracts`, puis appellent le service du module concerné dans `packages/core`. Aucune règle métier dans le processor.
2. **Jobs idempotents** :
   - l'identifiant du job est dérivé de l'entité (ex. `process-activity:{activityId}`), ce qui évite les doublons en file ;
   - un job rejoué ne crée pas de doublon en base, grâce à la transaction et à des écritures en « upsert ».
3. **Tentatives** : plusieurs essais avec backoff exponentiel pour les erreurs techniques (base, bucket, Redis). Une donnée invalide (trace illisible) est un échec définitif, sans nouvel essai.
4. **Échec définitif** : l'activité passe en `failed` et un événement `activity.failed` est publié. Politique fixée dans ADR-019 : 5 tentatives avec backoff exponentiel pour les erreurs techniques, échec définitif immédiat pour une trace invalide, colonnes `processing_error` et `processing_attempts`, relance depuis le backoffice.
5. **Publication après commit** : l'événement (`activity.processed`, topic `user:{userId}`) n'est publié qu'une fois la transaction validée, pour ne jamais annoncer un résultat absent de la base. Son contenu est minimal (`activityId`, `status`) : le mobile recharge l'activité par l'API (ADR-010).
6. **Concurrence réglée par file** : les jobs CPU (traitement des traces) ont une concurrence limitée ; on ajoute des instances du worker plutôt que d'augmenter la concurrence d'une seule.
7. **Arrêt propre** : à l'arrêt, le worker termine ses jobs en cours avant de quitter, pour que les déploiements n'interrompent pas un traitement.
8. **Corrélation** : le `requestId` reçu dans les données du job (ADR-009) est ajouté à tous les logs du job et aux événements publiés.

### Supervision

- Logs Pino par job (début, fin, durée, erreur).
- Les jobs en échec restent consultables dans Redis (`removeOnFail` limité, pas immédiat).
- Un tableau de bord (ex. Bull Board) pourra être exposé plus tard, protégé, ou les jobs en échec affichés dans le backoffice via l'API.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Exécuter les jobs dans l'API | Contraire à l'objectif : l'API doit rester légère (ADR-003) |
| File dans PostgreSQL (pg-boss, table de jobs) | Possible, mais Redis est déjà présent et BullMQ gère retries, priorités et concurrence |
| Tâches serverless (Lambda, fonctions) | Hors de l'infrastructure VPS, accès à la base et au bucket plus complexes |
| Worker sans NestJS (script Node) | Perd le partage des modules de `packages/core` et l'injection de dépendances |

## Conséquences

### Positives
- Les traitements lourds n'impactent ni l'API ni le temps réel.
- Mêmes règles métier que l'API grâce à `packages/core`.
- Retries et reprise automatiques en cas de panne temporaire.

### Négatives / risques
- **Redis critique** : un job mis en file peut être perdu si Redis tombe sans persistance (AOF à activer, ADR-001).
- **Idempotence à tester** : chaque job doit pouvoir être rejoué sans effet de bord.
- **Mémoire** : les traces longues (plusieurs heures) peuvent être volumineuses ; les traiter en flux si nécessaire.
- **Notifications APNs repoussées** : dépendent d'un compte Apple Developer (personnel ou d'entreprise), non disponible pour l'instant.

## Références
- [ADR-001 : Architecture globale](ADR-001-architecture-globale.md)
- [ADR-003 : Stack et architecture du backend](ADR-003-backend.md)
- [ADR-009 : Backend · app api](ADR-009-backend-api.md)
- BullMQ : https://docs.bullmq.io
- NestJS standalone applications : https://docs.nestjs.com/standalone-applications
