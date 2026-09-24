# ADR-006 : Stack détaillée de l'application mobile

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Détaille** : [ADR-002](ADR-002-mobile.md) (stack et architecture du mobile)
- **En lien avec** : [ADR-001](ADR-001-architecture-globale.md), [ADR-010](ADR-010-backend-realtime.md) (protocole temps réel), [ADR-014](ADR-014-revenuecat.md) (abonnements), [ADR-015](ADR-015-posthog.md) (analytics)

## Contexte

ADR-002 a fixé les grandes briques du mobile (Swift + SwiftUI, GRDB, Mapbox). Il reste à choisir les frameworks techniques pour :
- le **temps réel** : recevoir les événements du serveur WS (ex. valeurs officielles d'une activité traitée, ADR-001) ;
- l'**enregistrement GPS**, y compris écran verrouillé ;
- la **détection de la connectivité**, pour savoir quand synchroniser les activités enregistrées hors ligne ;
- la persistance locale et la carte, déjà retenues.

Principe directeur : **privilégier les frameworks natifs d'Apple** quand ils couvrent le besoin, et limiter les dépendances tierces à ce qui apporte une vraie valeur (GRDB, Mapbox).

## Décision

| Besoin | Choix | Type |
|---|---|---|
| UI | **SwiftUI** | Natif |
| Réseau REST | **URLSession** (async/await) | Natif |
| Temps réel (app ouverte) | **WebSocket natif** : `URLSessionWebSocketTask` | Natif |
| Notifications (app en arrière-plan ou fermée) | **APNs** + framework **UserNotifications** | Natif |
| Persistance locale | **SQLite via GRDB** | Dépendance (SPM) |
| Carte | **Mapbox Maps SDK for iOS** | Dépendance (SPM) |
| Abonnements | **RevenueCat** (`purchases-ios`), voir ADR-014 | Dépendance (SPM) |
| Analytics et feature flags | **PostHog** (`posthog-ios`), voir ADR-015 | Dépendance (SPM) |
| GPS | **Core Location** (`CLLocationManager`) | Natif |
| Connectivité | **`NWPathMonitor`** (framework Network) | Natif |
| Stockage des jetons | **Keychain** | Natif |

### WebSocket natif (`URLSessionWebSocketTask`)

- **Ouverture de la connexion** (protocole détaillé dans ADR-010) :
  1. l'app demande un jeton temps réel court à l'API (`POST /v1/realtime/token`, avec sa session) ;
  2. elle ouvre `wss://…/ws` avec ce jeton dans l'en-tête `Authorization: Bearer` ;
  3. elle s'abonne à son topic : `{ "a": "sub", "topic": "user:{userId}" }`.
- Messages JSON décodés avec `Codable`, au format du protocole versionné `{ v, t, id, data }` (ADR-010). Un message de version inconnue est ignoré.
- Le client WebSocket vit dans `Core/Network` et expose les événements sous forme d'`AsyncStream` aux features qui s'y abonnent.
- Ce que le natif ne fait pas et qu'il faut implémenter :
  - **heartbeat** : message applicatif `{ "a": "ping" }` toutes les 25 secondes (le serveur répond `pong`) pour détecter une connexion morte ;
  - **reconnexion automatique** avec backoff exponentiel, **avec un nouveau jeton à chaque fois** ; réaction selon le code de fermeture (`4001` jeton invalide, `4008` quota dépassé, `4009` redémarrage du serveur) ;
  - **déduplication** : un événement dont l'`id` a déjà été reçu est ignoré ;
  - **resynchronisation** : après chaque reconnexion, l'app interroge l'API pour récupérer l'état des activités en `processing`. Le WS n'est jamais la source de vérité (ADR-001).
- La connexion est **ouverte au premier plan uniquement** : iOS suspend l'app et coupe ses sockets peu après son passage en arrière-plan. Au retour au premier plan, reconnexion puis resynchronisation.

### Notifications push (APNs)

> **Priorité : plus tard.** Décision actée pour ne pas l'oublier, mais ce n'est pas une priorité du MVP. Tant qu'APNs n'est pas en place, l'app récupère l'état par l'API au retour au premier plan.

Le WebSocket ne peut pas fonctionner app fermée ou en arrière-plan : c'est une contrainte d'iOS, pas un choix. Pour prévenir l'utilisateur dans ce cas, on utilise les **notifications push d'Apple (APNs)** :

| État de l'app | Canal |
|---|---|
| Au premier plan | WebSocket : mise à jour immédiate de l'écran |
| En arrière-plan ou fermée | APNs : notification affichée par iOS |

- Au démarrage, l'app demande l'autorisation (`UNUserNotificationCenter`), s'enregistre auprès d'APNs (`registerForRemoteNotifications`) et **envoie son device token à l'API**, associé à l'utilisateur.
- Événements notifiés (à affiner) : **activité traitée** (valeurs officielles disponibles), kudos, commentaire, demande d'abonnement.
- Au tap sur une notification, l'app s'ouvre sur l'écran concerné et recharge les données par l'API.
- Les notifications silencieuses (`content-available`) peuvent servir à rafraîchir des données en arrière-plan, mais iOS les limite et ne garantit pas leur livraison : elles restent un bonus, jamais la seule source.
- **Impact côté serveur** (à détailler dans l'ADR de stack du backend) : endpoint d'enregistrement des device tokens, table des appareils (absente du modèle de la slide 09), envoi des notifications vers APNs par le backend (ex. un job du worker), et choix WS ou APNs selon que l'utilisateur est connecté au serveur `realtime`.

### SQLite avec GRDB

- `DatabasePool` (mode WAL) : lectures concurrentes pendant l'écriture des points GPS.
- Schéma versionné avec `DatabaseMigrator`.
- `ValueObservation` pour alimenter les stores SwiftUI quand les données changent.
- Tables locales principales : activités, points GPS de l'enregistrement en cours, **file de synchronisation** (envois en attente vers l'API et le bucket).

### Mapbox Maps SDK for iOS

- Installé via Swift Package Manager.
- Affichage des tracés (`LineLayer` sur source GeoJSON), styles personnalisés, cartes hors ligne (`OfflineManager` / `TileStore`).
- Les types Mapbox restent dans la couche présentation : le domaine manipule ses propres types de coordonnées (ADR-002).

### Core Location pour le GPS

- `CLLocationManager` avec `activityType` adapté au sport (`.fitness`, `.otherNavigation`…) et `desiredAccuracy = kCLLocationAccuracyBest` pendant l'enregistrement.
- **Enregistrement en arrière-plan** : mode `location` dans `UIBackgroundModes`, `allowsBackgroundLocationUpdates = true`, indicateur de localisation visible (`showsBackgroundLocationIndicator`).
- Autorisation « Pendant l'utilisation » suffisante si l'enregistrement démarre au premier plan ; les textes `NSLocationWhenInUseUsageDescription` (et `NSLocationAlwaysAndWhenInUseUsageDescription` si besoin) expliquent l'usage.
- Chaque point est écrit immédiatement dans GRDB, pour ne rien perdre si l'app est tuée.
- Le service GPS est isolé derrière un protocole du domaine `Recording` : on peut le remplacer par un faux fournisseur de positions dans les tests et le simulateur.

### `NWPathMonitor` pour la connectivité

- Un moniteur unique dans `Core/Network`, qui publie l'état (`satisfied`, `unsatisfied`, interface coûteuse ou non) sous forme d'`AsyncStream` ou d'état observable.
- Utilisé pour :
  - **déclencher la file de synchronisation** quand la connexion revient ;
  - afficher un indicateur « hors ligne » ;
  - éviter d'envoyer des traces lourdes sur une connexion coûteuse ou limitée (`isExpensive`, `isConstrained`), selon les préférences.
- **Limite assumée** : `NWPathMonitor` indique qu'une route réseau existe, pas que l'API est joignable (portail captif, serveur en panne). La synchronisation traite donc aussi les échecs réseau réels avec retries ; le moniteur n'est qu'un déclencheur.

## Alternatives envisagées

| Sujet | Alternative | Pourquoi écartée |
|---|---|---|
| WebSocket | Starscream, Socket.IO client | Dépendance inutile : `URLSessionWebSocketTask` couvre le besoin ; Socket.IO imposerait aussi un protocole spécifique côté serveur |
| WebSocket | Polling de l'API | Requêtes répétées, délai d'affichage |
| Notifications | Garder le WebSocket ouvert en arrière-plan | Impossible sur iOS : l'app est suspendue |
| Notifications | Service tiers (Firebase Cloud Messaging, OneSignal) | Intermédiaire inutile pour une app iOS seule ; APNs direct suffit |
| Réseau REST | Alamofire | URLSession + async/await suffit |
| Persistance | Core Data / SwiftData | Moins de contrôle SQL sur de gros volumes de points GPS, migrations moins prévisibles |
| Persistance | SQLite brut (C API) | Trop bas niveau : pas de migrations, d'observation ni de mapping |
| Carte | MapKit | Style peu personnalisable, pas de heatmap, pas de vraie carte hors ligne (ADR-002) |
| Connectivité | Reachability (SCNetworkReachability) | API ancienne, remplacée par `NWPathMonitor` |
| Connectivité | Pinger l'API régulièrement | Consomme batterie et données ; les échecs réels sont déjà gérés par la synchronisation |

## Conséquences

### Positives
- Seulement **quatre dépendances tierces** (GRDB, Mapbox, RevenueCat, PostHog), chacune isolée derrière un protocole ; tout le reste est natif et suit les versions d'iOS.
- Enregistrement fiable : points écrits au fil de l'eau, reprise possible après un arrêt de l'app.
- Synchronisation déclenchée automatiquement au retour du réseau.

### Négatives / risques
- **WebSocket natif** : heartbeat, reconnexion et resynchronisation sont à écrire et à tester soi-même.
- **Deux canaux temps réel à maintenir** (WS et APNs), et côté serveur une logique pour choisir lequel utiliser et éviter les doublons.
- **APNs** : compte Apple Developer, clé d'authentification APNs (`.p8`) à stocker comme secret côté serveur, gestion des tokens invalides (appareil désinstallé). L'utilisateur peut refuser les notifications : l'app doit fonctionner sans.
- **Batterie** : le GPS en haute précision est coûteux. Ajuster `distanceFilter` et la précision selon le sport, et arrêter les mises à jour dès la fin de l'enregistrement.
- **Validation App Store** : l'usage de la localisation en arrière-plan doit être justifié clairement.
- **`NWPathMonitor` peut se tromper** (réseau présent mais API injoignable) : ne jamais s'y fier seul.
- **Version minimale d'iOS** à fixer (iOS 17 envisagé pour le framework Observation) dans l'ADR sur l'architecture détaillée du mobile.

## Références
- [ADR-001 : Architecture globale](ADR-001-architecture-globale.md)
- [ADR-002 : Stack et architecture du mobile](ADR-002-mobile.md)
- URLSessionWebSocketTask : https://developer.apple.com/documentation/foundation/urlsessionwebsockettask
- Core Location : https://developer.apple.com/documentation/corelocation
- NWPathMonitor : https://developer.apple.com/documentation/network/nwpathmonitor
- GRDB.swift : https://github.com/groue/GRDB.swift
- Mapbox Maps SDK for iOS : https://docs.mapbox.com/ios/maps/
