# ADR-002 : Stack et architecture de l'application mobile

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : dossier d'architecture Like-Strava, slides 01 « Stack · application mobile » et 02 « Architecture mobile · features + hexagonal »
- **Dépend de** : [ADR-001](ADR-001-architecture-globale.md)

## Contexte

L'app mobile enregistre des activités (tracé GPS en continu, y compris en arrière-plan), les stocke sur l'appareil pour fonctionner sans réseau, les envoie à la plateforme (ADR-001) et les affiche sur une carte (tracés, parcours, heatmaps à terme). La cible est **iOS uniquement**.

## Décision

### Stack

| Brique | Choix | Rôle |
|---|---|---|
| Langage / UI | **Swift + SwiftUI** | Application iOS native |
| Persistance locale | **GRDB** (SQLite) | Activités, points GPS, file de synchronisation (offline-first) |
| Cartographie | **Mapbox Maps SDK for iOS** | Cartes, tracés, parcours |
| Géolocalisation | Core Location | Enregistrement GPS, indépendant du fournisseur de carte |

**Mapbox au lieu de MapKit** (le dossier d'architecture prévoyait MapKit) :
- styles de carte personnalisables (Mapbox Studio : fond sombre, relief, sentiers, pistes cyclables) ;
- couches data-driven (`LineLayer`, `HeatmapLayer`) adaptées aux longs tracés et aux futures heatmaps ;
- terrain et 3D, utiles pour le trail et le vélo ;
- cartes hors ligne (`OfflineManager` / `TileStore`), cohérent avec l'approche offline-first.

### Architecture : features + hexagonal

```
MyApp/
├── App/          point d'entrée + composition des dépendances (Di.swift)
├── Core/         Domain (types partagés), Database, Network (APIClient, auth, WebSocket), DesignSystem
└── Features/     Recording, Feed, Profile, Segments, Auth
    └── <Feature>/  Domain / Application / Infrastructure / Presentation
```

Flux d'une action utilisateur :

```
View SwiftUI → Store → Service → UseCase → Repository → SQLite local / API
```

Principes :
- **Un dossier par feature**, chaque feature découpée en couches hexagonales ; le métier (`Domain/`) ne dépend ni de SwiftUI, ni de GRDB, ni de Mapbox.
- **Une feature n'importe pas une autre feature** : ce qui est partagé remonte dans `Core/`.
- Les implémentations concrètes sont branchées dans `App/Di.swift`.

### Communication avec la plateforme (ADR-001)

- **REST** vers l'API pour toutes les données.
- **Envoi direct au bucket S3** des traces et médias, via des URLs pré-signées fournies par l'API.
- **WSS** vers le serveur WS pour recevoir les événements (ex. valeurs officielles d'une activité traitée). À la reconnexion, l'app resynchronise l'état par l'API.

Le détail des couches, des stores et de la synchronisation sera précisé dans un ADR dédié.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| MapKit | Style peu personnalisable, pas de heatmap native, pas de vraie carte hors ligne |
| React Native / Flutter | Pas de cible Android pour l'instant, GPS en arrière-plan plus délicat |
| Core Data / SwiftData | Moins de contrôle SQL sur de gros volumes de points GPS |
| MVVM simple / TCA | Métier dispersé dans les ViewModels (MVVM) ; dépendance lourde et boilerplate (TCA) |

## Conséquences

### Positives
- Carte au rendu soigné, tracés et heatmaps sans rendu maison.
- Mode hors ligne complet : données (GRDB) et fonds de carte (Mapbox).
- Métier testable sans UI, sans base et sans réseau.

### Négatives / risques
- **Coût Mapbox** : facturation au nombre d'utilisateurs actifs mensuels au-delà d'un palier gratuit. Vérifier la grille tarifaire avant la mise en production.
- **Jeton Mapbox** embarqué dans l'app : scopes minimaux, jamais commité en clair.
- **Intégration SwiftUI** de Mapbox moins native que MapKit : certaines interactions passeront par `MapView` (UIKit) via `UIViewRepresentable`.
- **Attribution** Mapbox/OpenStreetMap obligatoire sur la carte.
- **Verbosité** de l'architecture hexagonale (protocoles, UseCases) et **règles de dépendance non imposées par le compilateur** tant que tout est dans une seule cible.
- **Pas de partage de types avec le backend** (TypeScript) : les modèles réseau Swift seront générés depuis une spec OpenAPI (voir ADR-005).

## Références
- Dossier d'architecture Like-Strava, slides 01 et 02
- [ADR-001 : Architecture globale](ADR-001-architecture-globale.md)
- Mapbox Maps SDK for iOS : https://docs.mapbox.com/ios/maps/
- GRDB.swift : https://github.com/groue/GRDB.swift
