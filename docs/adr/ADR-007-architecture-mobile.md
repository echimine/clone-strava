# ADR-007 : Architecture détaillée de l'application mobile

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : dossier d'architecture Like-Strava, slide 02 « Architecture mobile · features + hexagonal »
- **Détaille** : [ADR-002](ADR-002-mobile.md) (principes), [ADR-006](ADR-006-stack-mobile.md) (stack détaillée)
- **En lien avec** : [ADR-008](ADR-008-mobile-offline-sync.md) (hors ligne et synchronisation)

## Contexte

ADR-002 pose le principe (découpage par feature, hexagonal, flux View → Store → Service → UseCase → Repository) et ADR-006 fixe les outils (URLSession, WebSocket natif, GRDB, Mapbox, Core Location, `NWPathMonitor`). Il reste à définir **comment le code s'organise et s'assemble** : rôle exact de chaque couche, emplacement des briques techniques, injection des dépendances, concurrence et tests.

Le fonctionnement hors ligne et la synchronisation font l'objet d'un ADR séparé (ADR-008).

## Décision

### Arborescence

```
MyApp/
├── App/
│   ├── StravaCloneApp.swift        point d'entrée
│   └── Di.swift                    composition root : crée et branche toutes les dépendances
├── Core/
│   ├── Domain/                     types partagés (identifiants, coordonnées, unités, erreurs)
│   ├── Database/                   AppDatabase (DatabasePool GRDB), migrations
│   ├── Network/
│   │   ├── APIClient               URLSession, encodage JSON, erreurs normalisées
│   │   ├── AuthSession             jeton Better Auth, stocké dans le Keychain
│   │   ├── WebSocketClient         URLSessionWebSocketTask, heartbeat, reconnexion
│   │   └── ConnectivityMonitor     NWPathMonitor
│   └── DesignSystem/               couleurs, typographie, composants SwiftUI réutilisables
└── Features/
    ├── Recording/
    │   ├── Domain/                 entités + protocoles (repositories, LocationProvider)
    │   ├── Application/            services + use cases
    │   ├── Infrastructure/         implémentations : GRDB, API, Core Location
    │   └── Presentation/           stores + views (Mapbox uniquement ici)
    ├── Feed/
    ├── Profile/
    ├── Segments/
    └── Auth/
```

### Rôle de chaque couche

| Couche | Rôle | Interdit |
|---|---|---|
| **View** (SwiftUI) | Affiche l'état du store, transmet les intentions de l'utilisateur | Appeler un service, un use case ou un repository |
| **Store** (`@Observable`, `@MainActor`) | État d'un écran, méthodes d'intention (`start()`, `refresh()`…), gestion du chargement et des erreurs affichables | Accès direct à GRDB, URLSession ou Core Location |
| **Service** | Coordonne dans la durée : flux GPS, chronomètre, plusieurs use cases (ex. `RecordingService`) | Dépendre de SwiftUI |
| **UseCase** | Une action métier, une règle (ex. `StartRecording`, `FinishRecording`, `LoadFeed`) | Dépendre d'une implémentation concrète |
| **Repository** (protocole dans `Domain/`) | Port d'accès aux données | — |
| **Repository** (implémentation dans `Infrastructure/`) | Adapter concret : GRDB, APIClient | Contenir des règles métier |

Les use cases triviaux sont acceptés pour garder un flux uniforme.

### Règles de dépendance

1. `Domain/` ne dépend que de Swift standard et de `Core/Domain` : ni SwiftUI, ni GRDB, ni Mapbox, ni Core Location.
2. `Application/` dépend de `Domain/` uniquement.
3. `Infrastructure/` implémente les protocoles de `Domain/` et utilise `Core/Database` et `Core/Network`.
4. `Presentation/` dépend de `Application/` et de `Core/DesignSystem`, jamais d'`Infrastructure/`.
5. **Une feature n'importe pas une autre feature.** Ce qui est partagé remonte dans `Core/`.
6. **Les types Mapbox restent dans `Presentation/`** : conversion depuis les coordonnées du domaine au moment de l'affichage.

### Emplacement des briques techniques (ADR-006)

| Brique | Emplacement | Exposée aux features par |
|---|---|---|
| APIClient, AuthSession | `Core/Network` | Utilisés par les repositories d'`Infrastructure/` |
| WebSocketClient | `Core/Network` | `AsyncStream` d'événements typés, filtrés par feature |
| ConnectivityMonitor | `Core/Network` | État observable + `AsyncStream` |
| Base GRDB | `Core/Database` | Repositories GRDB de chaque feature ; chaque feature déclare ses migrations |
| GPS (Core Location) | `Features/Recording/Infrastructure` | Protocole `LocationProvider` du domaine Recording |

### Injection des dépendances

- **Injection par initialiseur**, sans framework ni singleton global.
- `App/Di.swift` crée les objets partagés (base, APIClient, WebSocketClient, ConnectivityMonitor) puis, pour chaque feature, ses repositories, use cases et services.
- Chaque feature expose une **fabrique** qui construit ses stores ; les vues la reçoivent via l'environnement SwiftUI.
- Dans les tests et les previews, on branche des faux (repositories en mémoire, `LocationProvider` simulé).

### Concurrence et état

- **Swift Concurrency** (`async/await`, `AsyncStream`, acteurs) partout ; pas de Combine.
- **Mode Swift 6** (vérification stricte de la concurrence) activé dès le départ.
- Stores annotés `@MainActor` ; les services qui manipulent un état partagé (ex. tampon de points GPS) sont des **acteurs**.
- Framework **Observation** (`@Observable`) pour les stores, ce qui fixe la **version minimale à iOS 17**.

### Modularisation

- **Au départ : une seule cible Xcode**, avec l'arborescence ci-dessus. Les règles de dépendance sont vérifiées en revue de code.
- **Plus tard**, si les règles dérivent : extraction en packages Swift locaux (`Core`, un package par feature), pour que le compilateur les impose.

### Tests

| Cible | Outil | Approche |
|---|---|---|
| Domain, use cases, services | Swift Testing | Faux repositories et faux `LocationProvider` |
| Repositories GRDB | Swift Testing | Base SQLite en mémoire, migrations réelles |
| Repositories API | Swift Testing | `URLProtocol` simulé |
| Stores | Swift Testing | Services et use cases simulés, vérification des états |
| Parcours critiques (enregistrement) | XCUITest | Quelques scénarios, GPS simulé |

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| MVVM simple (View + ViewModel + services globaux) | Métier dispersé dans les ViewModels, couplage fort à GRDB et à l'API |
| TCA (The Composable Architecture) | Dépendance lourde, courbe d'apprentissage, boilerplate |
| Framework d'injection (Swinject, Factory) | L'injection par initialiseur suffit et reste vérifiée par le compilateur |
| Combine pour les flux | Swift Concurrency est le modèle recommandé et s'intègre à Observation |
| Packages Swift par feature dès le départ | Coût de mise en place élevé tant que les features bougent beaucoup |
| iOS 16 minimum | Imposerait `ObservableObject`/Combine ; iOS 17 couvre la grande majorité des appareils actifs |

## Conséquences

### Positives
- Le métier (calculs d'enregistrement, règles) se teste sans UI, sans base et sans réseau.
- GRDB, l'API, Mapbox ou Core Location peuvent changer sans toucher au domaine.
- Chaque feature se lit et se modifie dans un seul dossier.
- Swift 6 détecte les erreurs de concurrence à la compilation, important avec le GPS et le WebSocket en parallèle.

### Négatives / risques
- **Verbosité** : protocoles, use cases, fabriques et mappings entité ↔ modèle de persistance.
- **Règles non imposées par le compilateur** tant qu'on reste sur une seule cible.
- **Swift 6 strict** : certaines API (Core Location, Mapbox) demanderont des adaptations (`@preconcurrency`, isolation explicite).
- **iOS 17 minimum** : les appareils bloqués en iOS 16 ne pourront pas installer l'app.

## Références
- Dossier d'architecture Like-Strava, slide 02
- [ADR-002 : Stack et architecture du mobile](ADR-002-mobile.md)
- [ADR-006 : Stack détaillée du mobile](ADR-006-stack-mobile.md)
- [ADR-008 : Hors ligne et synchronisation du mobile](ADR-008-mobile-offline-sync.md)
- Observation : https://developer.apple.com/documentation/observation
- Swift Testing : https://developer.apple.com/documentation/testing
