# Recherche : Live Activity et Dynamic Island pour une Recording

- **Ticket** : [#45 Live Activity et Dynamic Island pour une Recording](https://github.com/echimine/clone-strava/issues/45) (carte wayfinder [#43](https://github.com/echimine/clone-strava/issues/43))
- **Date** : 2026-10-12
- **Question** : qu'est-ce qu'ActivityKit permet pour afficher une Recording sur l'écran verrouillé et dans la Dynamic Island, et à quelles contraintes ?
- **Sources** : documentation Apple (ActivityKit, WidgetKit, App Intents, SwiftUI, Info.plist), lue au format Markdown/JSON servi par `developer.apple.com/tutorials/data/documentation/…` ; Human Interface Guidelines « Live Activities » ; transcriptions WWDC23 « Meet ActivityKit » (10184) et « Discover streamlined location updates » (10180) ; deux fils des Apple Developer Forums (signalés comme tels, non officiels) ; spec XcodeGen ; article d'aide Strava. Tout a été lu le **2026-10-12**. Les citations sont verbatim. Rien n'a été testé sur appareil.

> Vocabulaire : **Recording** (« Enregistrement » dans l'app) est le terme du domaine : la capture en cours d'une Activity. **Live Activity** est le terme iOS du widget d'écran verrouillé et de la Dynamic Island ; ce n'est pas une Activity au sens du domaine.

---

## TL;DR

1. **Tout est disponible avec la cible actuelle (iOS 17.0).** ActivityKit date d'iOS 16.1, `Activity.update(_:)` d'iOS 16.2, `Text(timerInterval:pauseTime:…)` d'iOS 16.0 et `LiveActivityIntent` (boutons qui agissent sur la Recording) d'iOS 17.0. Rien n'oblige à monter la version minimale.
2. **Il faut une nouvelle cible : une widget extension**, plus la clé `NSSupportsLiveActivities = YES` dans l'Info.plist de l'app. Le projet n'a aujourd'hui aucune extension. XcodeGen (2.46.0 installé) sait générer une cible `app-extension`.
3. **La Live Activity ne calcule rien elle-même** : *« it can't access the network or receive location updates »*. Toute nouvelle valeur (distance, allure, état pause) vient de l'app via `activity.update(_:)`. Seul le chrono peut avancer tout seul, grâce aux vues datées (`Text(timerInterval:)`).
4. **Mises à jour depuis l'app en arrière-plan : autorisées, sans budget documenté.** Le budget horaire et le réglage « mises à jour fréquentes » concernent uniquement les **push** ActivityKit. Pour les mises à jour locales, Apple ne donne ni fréquence ni budget ; la HIG demande seulement de mettre à jour *« only when new content is available »*. Notre app tourne déjà en arrière-plan grâce au GPS (`CLBackgroundActivitySession`), ce qui est le cas où les mises à jour locales fonctionnent d'après les forums.
5. **Taille : 4 Ko au total** pour les données statiques et dynamiques réunies. Largement assez pour quelques nombres.
6. **Durée : 8 heures actives, puis jusqu'à 4 heures sur l'écran verrouillé**, soit 12 heures au plus. Au-delà de 8 h, le système termine la Live Activity et la retire de la Dynamic Island. Une Recording plus longue perd sa Live Activity.
7. **Chrono en pause** : `Text(timerInterval:pauseTime:countsDown:showsHours:)` accepte un `pauseTime` qui fige l'affichage. `ProgressView(timerInterval:)` n'a pas de paramètre de pause. Chaque pause ou reprise demande donc une mise à jour de l'état (nouvelle date de départ décalée, ou date de pause).
8. **Boutons pause / reprendre possibles** (iOS 17) via un `Button(intent:)` dont l'intent adopte `LiveActivityIntent`. L'intent s'exécute **dans le processus de l'app**, pas dans l'extension. Les boutons ne sont permis que dans les présentations **étendue** et **écran verrouillé**, pas en compact ni en minimal. Point à vérifier sur appareil : un article WidgetKit dit que les boutons sont inactifs tant que l'appareil est verrouillé, alors que la doc App Intents dit qu'un intent s'exécute par défaut *« including when the device is locked »*.
9. **Si l'app est tuée**, la Live Activity reste affichée avec son dernier contenu, et le chrono continue de tourner, donc il ment. Apple recommande de faire le ménage au lancement suivant. `staleDate` permet de marquer le contenu comme périmé si aucune mise à jour n'arrive.
10. **Strava** affiche *« elapsed time, distance, and pace »* sur l'écran verrouillé et dans la Dynamic Island, propose l'option iOS « More Frequent Updates », et son article d'aide ne mentionne **aucun bouton** : toucher la Live Activity ramène dans l'app.

---

## 1. Mise en place

### Plateformes et versions

- ActivityKit : **iOS 16.1+**, iPadOS 16.1+, Mac Catalyst 16.1+ ([ActivityKit](https://developer.apple.com/documentation/activitykit)). *« visionOS doesn't support Live Activities. »*
- Où elle s'affiche : *« On iPad and iPhone, it appears on the Lock Screen, in the Dynamic Island, and on the Home Screen. On Apple Watch, it appears in the Smart Stack. On Mac, it appears in the Menu bar. In CarPlay, it appears on the Home Screen. »* ([ActivityKit](https://developer.apple.com/documentation/activitykit))
- Historique ([ActivityKit updates](https://developer.apple.com/documentation/updates/activitykit)) : juin 2024, *« Support Live Activities in the Smart Stack in watchOS »* ; juin 2025, *« Live Activities automatically appear on the Mac in the Menu bar and in CarPlay »*.
- Les API utiles ici et leur version minimale, toutes ≤ iOS 17.0, la cible du projet (`apps/mobile/project.yml` : `deploymentTarget iOS "17.0"`, fixée par ADR-007) :

| API | Disponible depuis | Source |
|---|---|---|
| `Activity.request(…)` | iOS 16.1 | [ActivityKit](https://developer.apple.com/documentation/activitykit) |
| `Activity.update(_:)` | iOS 16.2 | [update(_:)](https://developer.apple.com/documentation/activitykit/activity/update(_:)) |
| `NSSupportsLiveActivitiesFrequentUpdates` | iOS 16.2 | [NSSupportsLiveActivitiesFrequentUpdates](https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates) |
| `Text(timerInterval:pauseTime:countsDown:showsHours:)` | iOS 16.0 | [SwiftUI Text](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)) |
| `ProgressView(timerInterval:countsDown:…)` | iOS 16.0 | [SwiftUI ProgressView](https://developer.apple.com/documentation/swiftui/progressview/init(timerinterval:countsdown:label:currentvaluelabel:)) |
| `LiveActivityIntent` | iOS 17.0 | [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent) |

### Cible et réglages

D'après [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) :

- *« To offer Live Activities, add code to your existing widget extension or create a new widget extension if your app doesn't already include one. »* L'interface est en SwiftUI + WidgetKit, dans l'extension ; ActivityKit gère le cycle de vie depuis l'app.
- *« make sure to select "Include Live Activity" when you add a widget extension target »* ; dans ce cas *« Xcode automatically creates a widget bundle for you that includes a widget and a Live Activity »*.
- Info.plist **de l'app** : *« add the `NSSupportsLiveActivities` key, then set the type to `Boolean` and its value to `YES` »*.
- Données statiques et dynamiques : *« The `ActivityAttributes` inform the system about static data that appears in the Live Activity. You also use `ActivityAttributes` to declare the required custom `ContentState` type that describes the dynamic data. »* Le `ContentState` est `Codable & Hashable`. Le type est utilisé par l'app (pour `request` / `update`) et par l'extension (pour le rendu), donc il doit être compilé dans les deux cibles.
- *« the extension target and your app are part of the same app group. As a result, you can store files and data in a shared container »* ([Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)). Pour une Live Activity seule, ce partage n'est pas nécessaire : tout passe par le `ContentState`.

### État du projet

- `apps/mobile/project.yml` (XcodeGen, source de vérité ; le `.xcodeproj` et l'`Info.plist` sont générés) contient trois cibles : `StravaClone` (application), `StravaCloneTests`, `StravaCloneUITests`. **Aucune extension**, aucun App Group, aucun fichier `.entitlements`.
- La spec XcodeGen ([ProjectSpec.md](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)) liste le type de cible `app-extension`, et l'option `embed` d'une dépendance vaut `true` par défaut pour une cible application. Une widget extension s'ajoute donc dans `project.yml` (type `app-extension`, `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension` dans son Info.plist), référencée en dépendance de `StravaClone`. Non essayé.
- `Info.plist` de l'app : `UIBackgroundModes: [location]` est déjà présent ; `NSSupportsLiveActivities` ne l'est pas.
- ADR-007 règle 5 : *« A feature does not import another feature. Anything shared moves up into `Core/`. »* Le type `ActivityAttributes` partagé entre l'app et l'extension n'a pas encore de place dans cette architecture (voir décisions).

### Réglages de l'utilisateur

- *« people can choose to deactivate Live Activities for an app in the Settings app »*. L'app lit `ActivityAuthorizationInfo().areActivitiesEnabled` et observe `activityEnablementUpdates` ([Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)).
- *« Live Activities are user-moderated similar to Notifications. Someone can easily dismiss or turn them off for your app altogether. »* (WWDC23 [Meet ActivityKit](https://developer.apple.com/videos/play/wwdc2023/10184/))
- Le nombre de Live Activities simultanées est limité, sans chiffre : *« the exact number may depend on a variety of factors »* ; *« starting a Live Activity may fail because a person's device may have reached its limit »*. Il faut donc gérer l'échec de `request` sans bloquer la Recording.
- Côté Strava, l'utilisateur doit aussi autoriser les Live Activities écran verrouillé dans Réglages > Face ID et code ([Strava](https://support.strava.com/hc/en-us/articles/39508401687693-Strava-Live-Activities-on-iOS)).

---

## 2. Démarrer, mettre à jour, terminer

### Démarrage

- *« You start a Live Activity in your app's code while the app is in the foreground with the `request(attributes:content:pushType:)` function. »* Avec `pushType: nil`, *« this activity can only receive updates locally »* (WWDC23 10184).
- *« In general, your app needs to be in the foreground to start a Live Activity. […] However, you can start a Live Activity while your app is in the background by using an app intent that conforms to `LiveActivityIntent`. »*
- Pour une Recording, le démarrage se fait naturellement au premier plan, au toucher de « Démarrer ».

### Mises à jour depuis l'app, sans push

- *« Use this function to update the Live Activity while your app is in the foreground or while it's in the background — for example, by using BackgroundTasks. »* ([update(_:)](https://developer.apple.com/documentation/activitykit/activity/update(_:)))
- *« Each Live Activity runs in its own sandbox, and — unlike a widget — it can't access the network or receive location updates. To update the dynamic data of an active Live Activity, use ActivityKit in your app or allow your Live Activities to receive ActivityKit push notifications. »*
- **Fréquence et budget des mises à jour locales : non documentés.** Ni la page `update(_:)`, ni l'article principal, ni WWDC23 10184 ne donnent de limite. Les seules phrases sur un budget parlent des push : *« The system allows for a certain budget of ActivityKit push notifications per hour. »* ; *« If you exceed the budget, the system may throttle your ActivityKit push notifications. »* ([Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)). La page ne dit pas si les mises à jour locales y sont décomptées.
- `NSSupportsLiveActivitiesFrequentUpdates` (iOS 16.2) : *« Set the corresponding value to `true` to enable your Live Activities to receive frequent updates with remote push notifications. »* Elle vise donc les push. *« People can deactivate frequent ActivityKit push notifications for your app in the Settings app »*, détectable via `frequentPushesEnabled`.
- Guide de conception (HIG) : *« Update a Live Activity only when new content is available. If the underlying content or status remains the same, maintain the same display until the underlying content or status changes. »* ([HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities))
- Animation : le système ignore `withAnimation` et applique ses propres transitions (texte flouté, SF Symbols) ; pour un chrono, `contentTransition(.numericText(countsDown:))`. Animations limitées à 2 s, et *« the system doesn't perform animations on Always-On displays with reduced luminance »* (HIG).

### Ce qui garde l'app vivante en arrière-plan

C'est la condition pour que `update(_:)` soit appelé pendant une Recording écran verrouillé.

- L'app tient déjà le GPS en arrière-plan : `Core/Location/CoreLocationProvider.swift` crée une `CLBackgroundActivitySession` et lit `CLLocationUpdate.liveUpdates(.fitness)` ; `RecordingService.start()` appelle `beginBackgroundTracking()`.
- WWDC23 [Discover streamlined location updates](https://developer.apple.com/videos/play/wwdc2023/10180/) : *« LiveActivity is the best way to enable background location updates. As long as your LiveActivity remains active, your app can receive updates without any other additional setup. »* Et pour `CLBackgroundActivitySession` : *« Your app still needs to have location in its UIBackgroundModes array »* ; *« If you don't have an outstanding session, then you must start the new session from the foreground, but you can only rejoin an existing one from the background. »*
- **Contradiction non résolue** : un développeur rapporte en juin 2025 que, dans un test minimal, les positions s'arrêtent environ 10 s après le passage en arrière-plan malgré une Live Activity visible, et reprennent avec une `CLBackgroundActivitySession` ([forum 788647](https://developer.apple.com/forums/thread/788647), aucune réponse d'Apple). Le projet tient déjà la session, donc il ne dépend pas de cette affirmation de la WWDC. À ne pas retirer la session sur la foi de la WWDC.
- Rapport communautaire (non officiel, 2022–2024) : `activity.update` depuis l'arrière-plan fonctionne quand l'app tourne *« with background location or Picture-in-picture mode »*, mais pas avec l'audio en arrière-plan sur appareil réel ([forum 717701](https://developer.apple.com/forums/thread/717701) ; la seule réponse d'Apple y est « Confirmed where? »).

### Taille

- *« Static and dynamic data for a Live Activity, including data for ActivityKit updates and ActivityKit push notifications, can't exceed a combined size of 4 KB. »* ([Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities))
- Paramètre `content` de `update(_:)` : *« The size of its `state` property can't exceed 4KB in size. »*
- Images : *« If you use an image asset that's larger than the size of the Live Activity presentation, the system might fail to start the Live Activity. »* Le tracé de l'Itinéraire, s'il devait apparaître, ne tient pas en 4 Ko sous forme de coordonnées brutes ; il faudrait le pré-rendre en image dans l'extension ou s'en passer. Constat, pas mesure.

### Durée de vie et fin

- *« A Live Activity can be active for up to eight hours unless its app or a person ends it before this limit. After the eight-hour limit, the system automatically ends the Live Activity, and immediately removes it from the Dynamic Island. However, the Live Activity remains on the Lock Screen until a person removes it or for up to four additional hours before the system removes it — whichever comes first. As a result, a Live Activity remains on the Lock Screen for a maximum of 12 hours. »*
- HIG : *« Live Activities work best for tracking short to medium duration activities that don't exceed eight hours. »*
- Fin : `end(_:dismissalPolicy:)`, avec un `ContentState` final (*« Always include an updated `ContentState` to ensure the Live Activity shows the latest and final content update after it ends »*). Politique `default` : reste jusqu'à 4 h sur l'écran verrouillé ; `immediate` : retirée tout de suite ; `after(_:)` : date choisie, plafonnée à 4 h. HIG : *« In most cases, 15 to 30 minutes is adequate. »*
- *« The system ignores attempts to update a Live Activity that ended. »* ([update(_:)](https://developer.apple.com/documentation/activitykit/activity/update(_:)))
- *« A person can remove your Live Activity from their Lock Screen at any time. This ends the Live Activity, but it doesn't end or cancel the person's action that started it. »* Supprimer la Live Activity ne doit donc pas arrêter la Recording. L'app peut le détecter via `activityStateUpdates`.

### App tuée ou plantée pendant la Live Activity

- *« the system may stop your app, or your app may crash while a Live Activity is active. When the app launches the next time, check if any activities are still active, update your app's stored Live Activity data, and end any Live Activity that's no longer relevant. »* La Live Activity survit donc au processus, avec son dernier contenu ; `Activity.activities` permet de la retrouver au lancement suivant.
- Conséquence déduite (non testée) : un `Text(timerInterval:)` continue d'avancer alors que plus rien n'est enregistré. Pour l'éviter, `staleDate` : *« At the specified date, the `activityState` changes to `stale` and `isStale` changes to `true`. »* L'app peut repousser cette date à chaque mise à jour, et la vue peut afficher un état « périmé » via `context.isStale`. Le choix de la marge (par exemple quelques dizaines de secondes sans point GPS) est une décision.
- Pas de fin automatique liée à la mort du processus : seule la limite des 8 h, l'utilisateur ou l'app terminent la Live Activity.

---

## 3. Le chrono qui avance seul, et la pause

- `Text(timerInterval: ClosedRange<Date>, pauseTime: Date? = nil, countsDown: Bool = true, showsHours: Bool = true)` : *« Creates an instance that displays a timer counting within the provided interval. »* `pauseTime` : *« If present, the date at which to pause the timer. The default is `nil` which indicates to never pause. »* ([doc](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)))
- Pour un chrono qui **monte** : `countsDown: false`. L'affichage est calculé par le système à partir des dates : il avance sans aucune mise à jour de l'app.
- Note de mise en page : *« In a widget, this `Text` becomes horizontally flexible and expands to fill the available width »* ; contraindre avec `frame(width:)`. À prendre en compte en présentation compacte, très étroite.
- `ProgressView(timerInterval:countsDown:…)` : progression continue entre deux dates. **Aucun paramètre de pause.** *« Date-relative progress views […] don't support custom styles. »* Peu utile pour une Recording, qui n'a pas de fin connue ; éventuellement pour une distance restante, mais celle-ci dépend du déplacement, pas du temps.
- **Figer pendant une pause** : deux options documentées, chacune demande un `update` au moment de la pause et un autre à la reprise.
  1. Garder `Text(timerInterval:)` et passer `pauseTime` = date de la pause. À la reprise, envoyer une nouvelle borne de départ décalée de la durée de pause (`début + durée totale des pauses`) et `pauseTime = nil`.
  2. Pendant la pause, remplacer le chrono par un texte statique (durée formatée par l'app).
- Le temps affiché est donc du **temps de déplacement** si l'on décale le départ, ou du **temps écoulé** si l'on ne le décale pas. Strava affiche *« elapsed time »*. C'est une décision produit (voir §7), liée au modèle de pause de la carte #43.
- Distance et allure ne sont **pas** dérivables d'une date : elles ne changent qu'au rythme des `update(_:)` envoyés par l'app.

---

## 4. Présentations et interactions

### Présentations

D'après [Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) et la [HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities) :

- **Écran verrouillé** : bannière en bas ; *« The system may truncate a Live Activity if its height exceeds 160 points. »* Marge standard 14 pt. Fond personnalisable (seulement ici).
- **Compacte** (une seule Live Activity active) : deux éléments de part et d'autre de la caméra, *« Keep content as narrow as possible »*, et les deux doivent ouvrir le même écran.
- **Minimale** (plusieurs Live Activities d'apps différentes) : *« If possible, display updated information rather than just a logo »* ; image ≤ 45 × 36,67 pt.
- **Étendue** (appui long, ou brièvement à chaque mise à jour avec alerte) : obligatoire ; zones `leading`, `trailing`, `center`, `bottom`.
- Tailles en points (HIG) : compacte 52,33 × 36,67 (écran 393 × 852) ou 62,33 × 36,67 (430 × 932) par côté ; étendue et écran verrouillé 371 ou 408 × 84–160.
- **Apple Watch (Smart Stack)** : pris en charge depuis juin 2024 ; **Mac et CarPlay** : affichage automatique depuis juin 2025 ([ActivityKit updates](https://developer.apple.com/documentation/updates/activitykit)) ; *« Buttons and toggles on Live Activities don't perform actions in CarPlay. »*
- Toucher la Live Activity ouvre l'app ; `widgetURL(_:)` donne un lien profond, sinon l'app reçoit un `NSUserActivity` de type `NSUserActivityTypeLiveActivity` ([Launching your app from a Live Activity](https://developer.apple.com/documentation/activitykit/launching-your-app-from-a-live-activity)).
- Contenu sensible : *« Live Activities are prominently visible and could be viewed by casual observers »* (HIG). Distance et allure ne le sont guère ; une position ou un nom de lieu le seraient davantage.

### Boutons pause / reprendre

- *« Like widgets, Live Activities can contain SwiftUI buttons and toggles to provide quick actions. […] adopt the App Intents framework and use the initializers for `Button` and `Toggle` that take an app intent. »*
- *« For a Live Activity interactive, adopt the `LiveActivityIntent` protocol. »* ; *« If you adopt the LiveActivityIntent or AudioPlaybackIntent protocol, the system runs the app intent in the app's process. »* ([Adding interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)). Le `perform()` s'exécute donc là où vivent `RecordingService` et le GPS ; l'intent doit être visible des deux cibles (référencé par le `Button` dans l'extension, exécuté dans l'app).
- `LiveActivityIntent` : *« An intent that starts, pauses, or otherwise modifies a Live Activity when it runs. »* ; *« When the system performs the intent, the system launches your app process without opening the app, performs the intent »* ([doc](https://developer.apple.com/documentation/appintents/liveactivityintent)).
- *« Live Activities can include buttons or toggles in the expanded and the Lock Screen presentation. »* Pas en compacte ni en minimale.
- HIG : *« Only include interactive elements for essential functionality that's directly related to your Live Activity and that people activate once or temporarily pause and resume, like music playback, workouts […]. If you offer interactivity, prefer limiting it to a single element »*. Et l'exemple d'Apple cite explicitement *« real-time fitness metrics and interactive controls to pause or cancel a workout »*.
- *« Toggle updates its appearance optimistically and indicates its new state immediately — without waiting for the result of the performed action. »* ; *« A button […] doesn't remain in a pressed state. As a result, use Toggle to indicate on/off functionality. »*
- **Écran verrouillé, contradiction à vérifier sur appareil** :
  - [Adding interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) : *« On a locked device, buttons and toggles are inactive and the system doesn't perform actions unless a person authenticates and unlocks their device. »*
  - [`AppIntent.authenticationPolicy`](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy) : la valeur par défaut `alwaysAllowed` *« allows the intent to run without authentication, including when the device is locked »*.
  - Selon la réponse, mettre en pause depuis l'écran verrouillé demande ou non Face ID. À tester avant de figer le design.
- **App tuée puis bouton touché** : le système relance le processus pour exécuter l'intent. Reprendre le GPS dans ce cas n'est pas garanti : WWDC23 10180 dit qu'une nouvelle `CLBackgroundActivitySession` doit être démarrée au premier plan, seule une session existante pouvant être rejointe depuis l'arrière-plan. Non testé.

---

## 5. Strava, pour référence

Source : [Strava Live Activities on iOS](https://support.strava.com/hc/en-us/articles/39508401687693-Strava-Live-Activities-on-iOS) (article d'aide, date exacte non affichée).

- *« Live Activities display elapsed time, distance, and pace. »* Pas de détail par sport dans l'article.
- Écran verrouillé, et Dynamic Island sur les modèles qui l'ont.
- iOS 16.1 ou plus.
- Option « More Frequent Updates » dans Réglages > Strava > Live Activities, qui rafraîchit les stats plus souvent au prix de la batterie. Ce réglage iOS correspond à la clé `NSSupportsLiveActivitiesFrequentUpdates`, qu'Apple documente pour les **push** ; l'article ne dit pas si Strava met à jour par push ou localement. Déduction, non vérifiée.
- Aucun bouton pause ou reprendre n'est mentionné ; *toucher la Live Activity ramène dans l'app*, où l'on peut arrêter.

---

## 6. Ce que cela implique pour la Recording (constats, pas décisions)

- Le chrono peut tourner sans réveiller l'app ; distance, allure ou vitesse et distance restante demandent des `update(_:)`. Leur rythme est à choisir, Apple n'impose ni ne conseille de chiffre pour les mises à jour locales.
- Une pause manuelle ou automatique implique au moins deux `update` (début et fin de pause). Une pause automatique qui oscille produirait autant de mises à jour.
- Le `ContentState` d'une Recording (quelques `Double`, deux `Date`, un état, un sport) tient très loin des 4 Ko.
- Les mises à jour depuis l'arrière-plan reposent sur le fait que le GPS garde l'app vivante. Pendant une pause, si le GPS est coupé ou ralenti (sujet de la recherche GPS de la carte), l'app peut être suspendue : la Live Activity resterait figée sur son dernier état, ce qui est correct pour une pause tant que le chrono est figé lui aussi.
- Une Recording de plus de 8 h perd sa Live Activity sans possibilité de la relancer depuis l'arrière-plan, sauf par un `LiveActivityIntent`.
- Le refus de l'utilisateur ou une limite système atteinte ne doivent jamais empêcher une Recording de démarrer.

---

## 7. Décisions ouvertes (renvoyées, non tranchées)

1. **Rendu visuel** de chaque présentation (écran verrouillé, compacte, minimale, étendue) et contenu selon le sport (allure ou vitesse, distance restante sur l'Itinéraire) : à prototyper, comme prévu dans la carte #43.
2. **Boutons pause / reprendre** dans la Live Activity (iOS 17, `LiveActivityIntent`) ou aucune interaction comme Strava ; si oui, `Button` ou `Toggle`, et politique d'authentification écran verrouillé, après test sur appareil.
3. **Chrono affiché** : temps écoulé (comme Strava) ou temps de déplacement, et méthode pour le figer en pause (`pauseTime` ou texte statique).
4. **Rythme des mises à jour locales** de la distance et de l'allure (par intervalle de temps, par pas de distance, ou à chaque point), avec l'effet batterie.
5. **`staleDate`** : marge avant d'afficher la Live Activity comme périmée, et rendu de l'état périmé ; ménage au lancement (`Activity.activities`) après un plantage.
6. **Politique de fin** : moment où la Live Activity se termine (arrêt, écran de fin, Enregistrer / Supprimer) et `dismissalPolicy` (`immediate`, `after`, `default`), contenu final affiché.
7. **Place du code dans l'architecture** (ADR-007) : où vit le type `ActivityAttributes` partagé par l'app et l'extension, quel composant appelle ActivityKit (un adaptateur dans `Features/Recording/Infrastructure` derrière un port, ou autre), nom et bundle id de l'extension dans `project.yml`.
8. **Push ActivityKit** : non nécessaire pour une Recording mise à jour par l'app ; à écarter explicitement ou non (et donc `NSSupportsLiveActivitiesFrequentUpdates`).
9. **Événements PostHog** liés à la Live Activity (refus, suppression par l'utilisateur, boutons), à rattacher au ticket des événements de l'enregistrement.

---

## Sources

- [ActivityKit](https://developer.apple.com/documentation/activitykit)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [Activity.update(_:)](https://developer.apple.com/documentation/activitykit/activity/update(_:))
- [Launching your app from a Live Activity](https://developer.apple.com/documentation/activitykit/launching-your-app-from-a-live-activity)
- [ActivityKit updates](https://developer.apple.com/documentation/updates/activitykit)
- [NSSupportsLiveActivitiesFrequentUpdates](https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)
- [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
- [AppIntent.authenticationPolicy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy) et [IntentAuthenticationPolicy](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy)
- [Text(timerInterval:pauseTime:countsDown:showsHours:)](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:))
- [ProgressView(timerInterval:countsDown:label:currentValueLabel:)](https://developer.apple.com/documentation/swiftui/progressview/init(timerinterval:countsdown:label:currentvaluelabel:))
- [Human Interface Guidelines : Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- WWDC23 [Meet ActivityKit (10184)](https://developer.apple.com/videos/play/wwdc2023/10184/)
- WWDC23 [Discover streamlined location updates (10180)](https://developer.apple.com/videos/play/wwdc2023/10180/)
- Forums Apple (non officiels) : [717701](https://developer.apple.com/forums/thread/717701), [788647](https://developer.apple.com/forums/thread/788647)
- [XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
- [Strava Live Activities on iOS](https://support.strava.com/hc/en-us/articles/39508401687693-Strava-Live-Activities-on-iOS)
- Dépôt : `apps/mobile/project.yml`, `apps/mobile/StravaClone/Core/Location/CoreLocationProvider.swift`, `apps/mobile/StravaClone/Features/Recording/*`, `docs/adr/ADR-007-mobile-architecture.md`
