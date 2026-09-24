# ADR-001 : Architecture globale

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : dossier d'architecture Like-Strava, slide 08 « Architecture globale » (et slide 10 pour l'exemple de flux)
- **Détaillé par** : [ADR-002](ADR-002-mobile.md), [ADR-003](ADR-003-backend.md), [ADR-004](ADR-004-backoffice.md), [ADR-005](ADR-005-monorepo.md)

## Contexte

Like-Strava est un clone de Strava. La plateforme doit :
- recevoir des activités sportives enregistrées sur mobile (traces GPS parfois volumineuses) ;
- calculer les **valeurs officielles** d'une activité (distance, temps, dénivelé, tracé, zone de confidentialité), ce qui est coûteux en calcul ;
- prévenir le mobile en temps réel quand un traitement est terminé ;
- offrir un backoffice pour administrer la plateforme ;
- protéger les données : un client ne doit jamais pouvoir contourner les règles métier.

## Décision

**Les clients passent par l'API, le traitement lourd est asynchrone.**

### Composants

| Composant | Techno | Rôle |
|---|---|---|
| App mobile | Swift + SwiftUI | Enregistrement et consultation des activités |
| Backoffice | Next.js | Administration de la plateforme |
| API | NestJS (REST) | Seul point d'entrée des clients : règles métier, écriture en base, mise en file des jobs, URLs pré-signées |
| Serveur WS | NestJS (WebSocket) | Pousse les événements au mobile |
| Worker | NestJS + BullMQ | Exécute les traitements lourds (ex. `process-activity`) |
| Redis | Redis | Files de jobs (BullMQ) et Pub/Sub entre worker, API et serveur WS |
| Base de données | PostgreSQL + PostGIS | Données métier et géospatiales |
| Stockage objet | Bucket S3 OVH | Traces brutes et médias |

### Flux

```
 Backoffice ──JSON/HTTP──┐
                         ▼
 App mobile ──JSON/HTTP──► NestJS api ──écriture──► PostgreSQL + PostGIS
   │  ▲   │                 │    │                        ▲
   │  │   │                 │    └─URL pré-signée─┐       │ écriture
   │  │   └──PUT/GET direct─┼──────────────► Bucket S3    │
   │  │                     │ enqueue / pub       ▲       │
   │  │                     ▼                     │ GET   │
   │  │                   Redis ──jobs──────► Worker ─────┘
   │  │                     ▲  ◄──pub « job fini »─┘
   │  │                     │ sub
   │  └──────WSS──────── NestJS WS
```

### Principes

1. **Les clients ne parlent qu'à l'API** (JSON/HTTP) pour les données. Ils ne contactent jamais PostgreSQL ni Redis.
2. **Seuls l'API et le worker écrivent en base.** Le serveur WS ne fait que relayer des événements.
3. **Le traitement lourd est asynchrone** : l'API enregistre la demande, met un job en file et répond immédiatement (`202 Accepted`). Le worker exécute le job hors de l'API.
4. **Les fichiers volumineux ne transitent pas par l'API** : l'API délivre une URL pré-signée, le client envoie ou télécharge directement depuis le bucket.
5. **Le temps réel passe par Redis** : le worker publie un événement (ex. `activity.processed`), le serveur WS y est abonné et le pousse au mobile par WSS. L'événement est un **signal au contenu minimal** : le mobile recharge ensuite les données par l'API, qui reste l'unique source de vérité (ADR-010).
6. **Le backoffice n'utilise pas le temps réel** : il n'est relié qu'à l'API.

### Exemple : création d'une activité (slide 10, détaillé dans un ADR dédié)

1. Le mobile crée l'activité (`POST /activities`, statut `pending`) et reçoit une URL pré-signée.
2. Il envoie la trace compressée directement au bucket, puis appelle `POST /activities/:id/complete`.
3. L'API passe l'activité en `processing`, met en file `process-activity` et répond `202`.
4. Le worker lit la trace, calcule les métriques et le tracé, écrit le résultat en transaction (`processed`), puis publie `activity.processed`.
5. Le serveur WS pousse l'événement au mobile, qui recharge l'activité par l'API et affiche les valeurs officielles.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Traitement synchrone dans l'API | L'API resterait bloquée pendant les calculs, temps de réponse longs et imprévisibles pour le mobile, pas de retries |
| Envoi des traces à travers l'API | Charge réseau et mémoire inutile sur l'API, alors que le bucket sait recevoir les fichiers directement |
| Polling du mobile au lieu du WebSocket | Requêtes répétées inutiles, délai d'affichage des valeurs officielles |
| Accès direct des clients à la base (ex. BaaS type Supabase) | Règles métier contournables, logique répartie entre clients et politiques de base |
| Microservices par domaine | Coût opérationnel disproportionné pour la taille du projet (voir ADR-003) |

## Conséquences

### Positives
- L'API reste rapide : elle ne fait que valider, enregistrer et mettre en file.
- Le worker et le serveur WS se dimensionnent indépendamment de l'API.
- Les règles métier et d'accès sont centralisées côté serveur.
- Les traitements échoués peuvent être rejoués (retries BullMQ) sans intervention du client.

### Négatives / risques
- **Redis est critique** : il porte les files et le Pub/Sub. Prévoir la persistance (AOF) et de la supervision.
- **Push WS manqué** : si le mobile n'est pas connecté au moment de l'événement, il doit récupérer l'état de l'activité par l'API à la reconnexion. Le WS est une optimisation, pas la source de vérité.
- **Cohérence éventuelle** : entre `processing` et `processed`, les valeurs affichées sont provisoires (calculées localement par le mobile).
- **Échecs de traitement** : le statut `failed` existe dans le modèle, mais la politique (nombre de tentatives, notification du mobile) reste à définir dans l'ADR sur le flux de création d'activité.
- **Plus de composants à opérer** : API, WS, worker, Redis, PostgreSQL, bucket.

## Références
- Dossier d'architecture Like-Strava, slides 08 et 10
- [ADR-002 : Mobile](ADR-002-mobile.md)
- [ADR-003 : Backend](ADR-003-backend.md)
- [ADR-004 : Backoffice](ADR-004-backoffice.md)
- [ADR-005 : Monorepo](ADR-005-monorepo.md)
