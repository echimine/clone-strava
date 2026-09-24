# ADR-008 : Hors ligne et synchronisation de l'application mobile

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : dossier d'architecture Like-Strava, slides 09 « Entités métier » et 10 « Feature · création d'activité » (côté mobile)
- **Dépend de** : [ADR-001](ADR-001-architecture-globale.md), [ADR-006](ADR-006-stack-mobile.md), [ADR-007](ADR-007-architecture-mobile.md)

## Contexte

Une sortie sportive se fait souvent sans réseau (montagne, forêt, zone blanche). L'app doit :
- **enregistrer une activité sans aucune connexion**, sans jamais perdre de points ;
- **l'envoyer plus tard**, automatiquement, dès que le réseau revient, même si l'app a été fermée entre-temps ;
- afficher des **valeurs provisoires** calculées localement, puis les **valeurs officielles** calculées par le worker (ADR-001) ;
- consulter les données déjà chargées (fil, profil, activités) hors ligne.

La création d'une activité côté serveur se fait en plusieurs appels (slide 10) : création, envoi de la trace au bucket, puis `complete`. Chacun peut échouer ou être interrompu.

## Décision

### 1. La base locale est la source de vérité de l'interface

- Les écrans lisent **uniquement GRDB**, via `ValueObservation` (ADR-006).
- Le réseau ne met pas à jour l'écran directement : il **écrit dans GRDB**, et l'écran se met à jour tout seul.
- Conséquence : un écran fonctionne de la même façon avec ou sans réseau.

### 2. Cycle de vie local d'une activité

```
recording ─► recorded ─► created ─► trace_uploaded ─► processing ─► processed
                │           │              │                │
                └───────────┴──────────────┴────────────────┴──► failed
```

| État local | Signification | Étape serveur (slide 10) |
|---|---|---|
| `recording` | Enregistrement en cours, points écrits au fil de l'eau | — |
| `recorded` | Terminé et validé localement, rien encore envoyé | — |
| `created` | `POST /activities` réussi, URL pré-signée reçue | 1 à 4 |
| `trace_uploaded` | `PUT trace.json.gz` réussi vers le bucket | 5 et 6 |
| `processing` | `POST /activities/:id/complete` a répondu `202` | 7 à 12 |
| `processed` | Valeurs officielles reçues (WS ou API) | 26 |
| `failed` | Erreur définitive (voir règle 5) | — |

L'état est **enregistré en base à chaque étape** : si l'app est tuée, la synchronisation reprend exactement là où elle s'était arrêtée.

### 3. File de synchronisation

- Une table GRDB `sync_operation` : type d'opération, entité concernée, nombre de tentatives, prochaine tentative, dernière erreur.
- Opérations du MVP : `create_activity`, `upload_trace`, `complete_activity`. D'autres s'ajouteront (modifier ou supprimer une activité, kudos, commentaire).
- **Ordre garanti par entité** : on n'envoie pas la trace d'une activité avant sa création.
- **Déclencheurs** : fin d'un enregistrement, retour du réseau (`NWPathMonitor`), retour de l'app au premier plan, et tâche de fond iOS (`BGTaskScheduler`) pour vider la file quand l'app n'est pas ouverte.
- **Envoi de la trace en arrière-plan** : le `PUT` vers le bucket utilise une `URLSession` de fond (`background` configuration), qui continue même si l'utilisateur quitte l'app.

### 4. Idempotence : l'identifiant est généré par l'app

- L'UUID de l'activité est **créé sur le téléphone** au début de l'enregistrement (slide 09 : « généré par le client »).
- Si un appel échoue sans réponse (coupure au mauvais moment), l'app **le rejoue avec le même UUID**. Le serveur doit reconnaître l'activité existante au lieu d'en créer une deuxième.
- `complete` doit aussi pouvoir être rejoué sans effet de bord.

### 5. Tentatives et erreurs

| Type d'erreur | Traitement |
|---|---|
| Pas de réseau, timeout, erreur 5xx | Nouvelle tentative avec backoff exponentiel (plafonné) |
| 401 (session expirée) | Rafraîchissement de la session, puis nouvelle tentative |
| URL pré-signée expirée (403 du bucket) | Demande d'une nouvelle URL à l'API, puis nouvel envoi |
| Erreur 4xx de validation | Arrêt, activité en `failed`, message à l'utilisateur avec possibilité de corriger ou supprimer |

Une activité en `failed` n'est **jamais supprimée automatiquement** : ses points restent sur le téléphone.

### 6. Valeurs provisoires puis officielles

- À la fin de l'enregistrement, l'app calcule et affiche des **valeurs provisoires** (distance, durée, dénivelé).
- Quand l'activité passe en `processed`, les **valeurs officielles** remplacent les provisoires. Elles sont **toujours lues par l'API** (`GET /v1/activities/:id`), déclenchée :
  - par le WebSocket si l'app est ouverte : l'événement `activity.processed` ne contient que `activityId` et `status` (ADR-010), et sert de signal pour recharger ;
  - sinon au retour au premier plan et après chaque reconnexion WS, où l'app demande l'état de ses activités en `processing`.
- Plus tard, par une notification APNs (ADR-006, priorité basse).

### 7. Conservation des données locales

- Les **points GPS bruts** restent sur le téléphone jusqu'à `processed`, puis sont supprimés (le serveur garde la trace brute dans le bucket). Le tracé simplifié est conservé pour l'affichage.
- Les données lues (fil, profils, activités des autres) sont **mises en cache** dans GRDB pour la consultation hors ligne, et rafraîchies quand le réseau est là.
- **Conflits** : pour le MVP, le serveur fait foi. Une modification locale envoyée écrase la version serveur ; une donnée reçue du serveur écrase le cache local.

## Points à trancher avec le backend

**Tranchés dans [ADR-019](ADR-019-flux-creation-activite.md)** :
- `POST /v1/activities` avec un UUID existant du même utilisateur : `200` avec l'activité existante (et une nouvelle URL si elle est encore `pending`) ; `409` si l'UUID appartient à un autre utilisateur ;
- nouvelle URL pré-signée : `POST /v1/activities/:id/upload-url` ;
- passage en `failed` après 5 tentatives (ou immédiatement pour une trace invalide), annoncé par l'événement `activity.failed` ou la resynchronisation ;
- URLs pré-signées valables 15 minutes.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Écrans alimentés directement par l'API, cache optionnel | Écrans vides ou en erreur hors ligne, deux chemins de code (avec et sans réseau) |
| Un seul appel « tout-en-un » (métadonnées + trace dans l'API) | Contredit ADR-001 : les fichiers volumineux ne passent pas par l'API |
| Identifiant généré par le serveur | Impossible de rejouer un appel sans risque de doublon, activité sans identifiant tant qu'on est hors ligne |
| Envoi uniquement quand l'app est ouverte | Activités bloquées si l'utilisateur n'ouvre pas l'app après sa sortie |
| Synchronisation bidirectionnelle complète (CRDT, résolution de conflits) | Disproportionné pour le MVP : l'utilisateur est le seul à modifier ses activités |

## Conséquences

### Positives
- Aucune perte d'activité, même sans réseau ou si l'app est tuée.
- Envoi automatique, sans action de l'utilisateur.
- Les écrans ont un seul chemin de code, qu'il y ait du réseau ou non.
- Les appels peuvent être rejoués sans créer de doublons.

### Négatives / risques
- **Complexité** : machine à états, file de synchronisation et reprise sont à tester soigneusement (coupures à chaque étape).
- **Tâches de fond iOS** : `BGTaskScheduler` ne garantit ni le moment ni la fréquence d'exécution ; l'envoi reste principalement déclenché par l'ouverture de l'app et le retour du réseau.
- **Stockage** : les points bruts des activités non envoyées peuvent occuper de la place ; prévoir un indicateur si des activités attendent depuis longtemps.
- **Dépendance au backend** : l'idempotence et le renouvellement des URLs doivent être implémentés côté serveur.

## Références
- Dossier d'architecture Like-Strava, slides 09 et 10
- [ADR-001 : Architecture globale](ADR-001-architecture-globale.md)
- [ADR-006 : Stack détaillée du mobile](ADR-006-stack-mobile.md)
- [ADR-007 : Architecture détaillée du mobile](ADR-007-architecture-mobile.md)
- Background URLSession : https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)
- BGTaskScheduler : https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler
