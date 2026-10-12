# Recherche : GPS en arrière-plan et pause automatique sur iOS

- **Ticket** : [#44 GPS en arrière-plan et pause automatique sur iOS](https://github.com/echimine/clone-strava/issues/44) (carte wayfinder [#43](https://github.com/echimine/clone-strava/issues/43))
- **Date** : 2026-10-12
- **Contexte** : la **Recording** (« Enregistrement » dans l'app) est la capture en cours d'une Activity, du démarrage jusqu'à ce que l'athlète l'enregistre ou la supprime (`CONTEXT.md`). ADR-008 (hors ligne, état local `recording`, aucun point perdu même si l'app est tuée), ADR-027 (un seul flux GPS partagé par la carte et la Recording, `LocationBroadcaster`).
- **Question** : comment configurer le GPS pour une Recording fiable en arrière-plan et écran verrouillé, et comment détecter un arrêt pour la pause automatique ?
- **Sources** : documentation Apple Core Location et Core Motion (lue via les pages JSON de developer.apple.com), sessions WWDC23 10180 et WWDC24 10212 (transcriptions officielles), trois fils des forums développeurs Apple (dont deux avec réponse acceptée d'un ingénieur Apple), guide d'efficacité énergétique Apple (archive), centre d'aide Strava, billet d'ingénierie Strava de 2014 (copie Wayback Machine), code du repo à `b35c7a2`. Tout a été lu le **2026-10-12**. Les citations sont verbatim, en anglais.

> Ce document établit des faits. Il ne tranche pas : les choix sont listés au §8 et renvoyés aux tickets de la carte.

---

## TL;DR

1. **L'API actuelle est la bonne pour iOS 17+.** `CLLocationUpdate.liveUpdates(.fitness)` + `CLBackgroundActivitySession`, déjà utilisés par `CoreLocationProvider`, sont la voie qu'Apple présente pour le suivi en arrière-plan avec l'autorisation « Lorsque l'app est active ». Avec cette API, Core Location peut **relancer l'app en arrière-plan** après une suspension ou une terminaison (crash, mémoire), à condition que l'app **recrée immédiatement au lancement** la session et la boucle `liveUpdates`. L'ancienne API (`startUpdatingLocation`) arrête tout si l'app est tuée.
2. **« Toujours » n'est pas nécessaire.** Mode d'arrière-plan `location` + autorisation « Lorsque l'app est active » + `CLBackgroundActivitySession` démarrée au premier plan suffisent. L'indicateur bleu (barre ou pastille) s'affiche alors en arrière-plan ; c'est lui qui garde l'app « en usage ». WWDC23 dit qu'une Live Activity active joue le même rôle, mais un fil des forums Apple de 2025 (sans réponse d'Apple) rapporte que non : seule la session est confirmée. Une session ne se crée qu'au premier plan et ne fait que se *rejoindre* au relancement ; Apple déconseille d'arrêter `liveUpdates` pendant un arrêt, sous peine de ne jamais être relancé. Le projet a déjà les deux clés `Info.plist` requises.
3. **Ce qui manque aujourd'hui pour la fiabilité** : aucun `AppDelegate` ne recrée la session et la boucle au relancement ; la Recording en cours n'est pas persistée (dépôt GRDB en `TODO`), donc rien ne dit au lancement qu'il faut reprendre ; les erreurs de `liveUpdates` sont avalées ; les mises à jour sans position (`isStationary`, diagnostics) sont jetées ; le tampon du `LocationBroadcaster` (16 valeurs, les plus récentes) peut perdre des points si l'écriture GRDB prend du retard.
4. **Pause automatique : Core Location fournit un signal, pas une règle.** `liveUpdates` met lui-même les mises à jour en pause quand l'appareil est immobile « for a sufficient amount of time » et envoie une dernière mise à jour avec `isStationary == true` (iOS 17) / `stationary` (iOS 18). Le délai n'est pas documenté. La vitesse (`CLLocation.speed`, `speedAccuracy`) et `CMMotionActivityManager` (`stationary`, `running`, `cycling`, avec un niveau de confiance) sont les autres signaux. Core Motion exige `NSMotionUsageDescription`, absente aujourd'hui.
5. **Strava sépare course et vélo.** Vélo : GPS, pause après **plus de 10 s** sans mise à jour à vitesse positive, reprise dès qu'un point est **à une distance minimale** du point de pause **et** au-dessus d'une **vitesse minimale** ; la distance pendant la pause est la **ligne droite** entre le dernier point en mouvement et le premier après reprise (élimine la dérive GPS à l'arrêt). Course : accéléromètre (« jerk » moyenné), pause/reprise en **environ 1 s**, reprise seulement en courant, avec une reprise de secours par GPS. Ces chiffres datent de 2014 ; l'aide Strava actuelle confirme GPS pour le vélo et accéléromètre pour la course, sans seuils. Pause automatique activée par défaut pour le vélo ; Strava conseille de la couper pour la marche et la randonnée.
6. **Batterie** : Apple ne chiffre pas le coût. Les leviers documentés sont la précision demandée, la pause automatique et l'arrêt des mises à jour. `liveUpdates` n'expose ni `desiredAccuracy` ni `distanceFilter` : seul le choix de `LiveConfiguration` est réglable. Un chiffrage demande une mesure sur appareil.

---

## 1. Les deux API de localisation continue

### 1.1 `CLLocationUpdate.liveUpdates` (iOS 17+, utilisée aujourd'hui)

- [`liveUpdates(_:)`](https://developer.apple.com/documentation/corelocation/cllocationupdate/liveupdates(_:)) : *« Tells Core Location to start delivering the location updates it produces for the configuration you specify. »* Signature : `static func liveUpdates(_ configuration: CLLocationUpdate.LiveConfiguration = .default) -> CLLocationUpdate.Updates`. Le seul réglage est la [`LiveConfiguration`](https://developer.apple.com/documentation/corelocation/cllocationupdate/liveconfiguration) : `default`, `airborne`, `automotiveNavigation`, `fitness`, `maritime`, `otherNavigation`. Il n'y a **ni `desiredAccuracy` ni `distanceFilter`**.
- [`.fitness`](https://developer.apple.com/documentation/corelocation/cllocationupdate/liveconfiguration/fitness) : *« The value that configures positioning for dedicated fitness sessions. »* Le [`CLActivityType.fitness`](https://developer.apple.com/documentation/corelocation/clactivitytype/fitness) correspondant précise : *« dedicated fitness sessions, such as walking workouts, running workouts, cycling workouts »*, *« This activity might cause the system to pause location updates when the user doesn't move a significant distance over a period of time »* et *« When activityType is fitness, the system disables indoor positioning. »*
- [`.otherNavigation`](https://developer.apple.com/documentation/corelocation/cllocationupdate/liveconfiguration/othernavigation) : *« transportation that doesn't, or may not, adhere to roads, such as cycling, scooters, trains, boats, and off-road vehicles. »* Côté `CLActivityType`, Apple réserve cette valeur aux sessions *« that aren't workouts »* et renvoie les séances sportives vers `fitness`.
- WWDC23 : *« If your app is already using a particular CLActivityType with existing location updates API, then you can choose a corresponding LiveConfiguration member to have the same location experience »* ([WWDC23 10180](https://developer.apple.com/videos/play/wwdc2023/10180/)).

**Pause et reprise intégrées** (WWDC23 10180) : *« once the device is in stationary state for a sufficient amount of time, CLLocationUpdate API will recognize this and trigger Automatic Pause. When pause is triggered, we will send an update with a non-nil location and isStationary flag marked as True. […] Later, when the device becomes non-stationary, updates will automatically resume without any user interaction. With this resuming update, we will send isStationary marked as False »*. La pause ne se désactive pas : contrairement à `CLLocationManager`, il n'y a pas d'équivalent de `pausesLocationUpdatesAutomatically = false`.

### 1.2 `CLLocationManager` (API historique)

- [`activityType`](https://developer.apple.com/documentation/corelocation/cllocationmanager/activitytype) : sert d'indice pour décider quand mettre en pause ; valeur par défaut `.other`.
- [`desiredAccuracy`](https://developer.apple.com/documentation/corelocation/cllocationmanager/desiredaccuracy) : défaut iOS `kCLLocationAccuracyBest` ; sans précision complète autorisée, la valeur est ignorée (`kCLLocationAccuracyReduced`).
- [`distanceFilter`](https://developer.apple.com/documentation/corelocation/cllocationmanager/distancefilter) : défaut `kCLDistanceFilterNone`.
- [`allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates) : défaut `false`. À `true`, *« Core Location configures the system to keep the app running to receive continuous background location updates, and arranges to show the background location indicator (blue bar or pill) if needed »*. Le mettre à `true` sans `UIBackgroundModes`/`location` est *« a fatal error that terminates the app »*.
- [`pausesLocationUpdatesAutomatically`](https://developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically) : défaut `true`. **Piège** : *« For apps that have in-use authorization, a pause to location updates ends access to location changes until the app launches again and is able to restart those updates. »* Avec cette API, une pause système pendant un arrêt au feu peut donc couper la Recording jusqu'au retour au premier plan.
- [`startUpdatingLocation()`](https://developer.apple.com/documentation/corelocation/cllocationmanager/startupdatinglocation()) : *« If your app is terminated, the delivery of new location events stops altogether. »*

### 1.3 Ce que chaque option garantit selon l'état de l'app

| État de l'app | `liveUpdates` + `CLBackgroundActivitySession` | `CLLocationManager` + `allowsBackgroundLocationUpdates` |
|---|---|---|
| Premier plan | Mises à jour | Mises à jour |
| Arrière-plan, écran verrouillé | Mises à jour, indicateur bleu | Mises à jour, indicateur bleu |
| Immobile | Pause automatique, `isStationary == true`, l'app peut être **suspendue** puis réveillée à la reprise, *« no action is required »* | Pause si `pausesLocationUpdatesAutomatically` ; avec « Lorsque l'app est active », plus aucune mise à jour jusqu'au prochain lancement |
| Suspendue | *« as soon as updates are available […] we will unsuspend your app »* | Mises à jour mises en file, livrées au réveil |
| Terminée (crash, mémoire) | *« We will recover your app as soon as location updates are available by launching it in the background »*, à condition de recréer session et boucle **immédiatement** | Plus aucune mise à jour (*« stops altogether »*) |

Sources : [WWDC23 10180](https://developer.apple.com/videos/play/wwdc2023/10180/), [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), pages `CLLocationManager` ci-dessus.

**Relancement après terminaison** (WWDC23 10180) : *« You need to restart the updates by calling liveUpdates, and if your app was previously using a background activity session then you also need to recreate a CLBackgroundActivitySession. […] this recreation allowed your app to rejoin that existing session from the background »* et *« Your app should perform any recreation immediately upon receiving background app launch. […] we have placed the recreation in UIApplicationDelegate's - didFinishLaunchingWithOptions »*.

WWDC24 précise la fenêtre : *« Core Location doesn't keep track of these explicit and implicit sessions forever. Instead, it does so for only a few seconds after the app is launched again […] So your job […] is to make sure that your process launch logic knows what features it has been tasked with pursuing, and re-takes session objects or resumes iterating liveUpdates […] as soon as it can »* ([WWDC24 10212](https://developer.apple.com/videos/play/wwdc2024/10212/)).

Pour une app SwiftUI, Apple documente le montage : un état partagé qui détient `CLLocationManager` et `CLBackgroundActivitySession`, un `AppDelegate` branché par `@UIApplicationDelegateAdaptor` qui, dans `application(_:didFinishLaunchingWithOptions:)`, relance `liveUpdates` et recrée la session si elles étaient actives (drapeaux persistés dans `UserDefaults` dans l'exemple) ([Supporting live updates in SwiftUI and Mac Catalyst apps](https://developer.apple.com/documentation/corelocation/supporting-live-updates-in-swiftui-and-mac-catalyst-apps)).

**Non établi** : WWDC23 range *« user close »* (fermeture par le sélecteur d'apps) parmi les causes de terminaison, puis dit que l'API récupère l'app *« in most cases »*, sans préciser lesquels. Le comportement après une fermeture volontaire par l'athlète est à vérifier sur appareil.

### 1.4 `CLBackgroundActivitySession`

- [Doc](https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession-3mzv3) : *« Use CLBackgroundActivitySession to start a background activity session that allows a when-in-use authorized app to receive location updates or monitoring events. »*
- WWDC23 : *« Just creating the session displays the indicator when your app is in the background »* ; *« object deallocation will automatically invalidate the session »* ; *« Your app still needs to have location in its UIBackgroundModes array »* ; *« If you don't have an outstanding session, then you must start the new session from the foreground, but you can only rejoin an existing one from the background. »*
- [`invalidate()`](https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession-3mzv3/invalidate()) : *« After you invalidate a session, it can't become active again and you need to create a new session »*.
- WWDC23 : *« LiveActivity is the best way to enable background location updates. As long as your LiveActivity remains active, your app can receive updates without any other additional setup. »* Lien direct avec [#45](https://github.com/echimine/clone-strava/issues/45) (Live Activity).
- **Contredit sur le terrain, non tranché par Apple** : un fil des forums développeurs Apple de juin 2025, [« Live Activity does not work as a proxy for CLBackgroundActivitySession »](https://developer.apple.com/forums/thread/788647), rapporte : *« the location updates stop shortly (10 seconds, this is the normal "grace period" described) after backgrounding the app, even when the live activity is visible. If I acquire a CLBackgroundActivitySession, location updates continue in the background. »* Reproduit dans le simulateur. **0 réponse**, aucune d'Apple (lu le 2026-10-12). Le seul comportement confirmé des deux côtés est donc celui de `CLBackgroundActivitySession`.
- **Rejoindre, pas recréer** : réponse acceptée d'un ingénieur Apple ([forum 767460](https://developer.apple.com/forums/thread/767460), nov. 2024) : *« A new CLBackgroundActivitySession can only be started from Foreground. From background only an existing running CLBAS session can be continued. »* Une session invalidée avant la terminaison ne peut donc pas être reprise au relancement en arrière-plan : il ne faut **pas** l'invalider tant que la Recording n'est pas terminée.
- **Ne pas arrêter `liveUpdates` pendant une pause** : réponse acceptée d'un ingénieur Apple ([forum 810433](https://developer.apple.com/forums/thread/810433), déc. 2025) : *« When the stationary property is set, you will stop getting updates until the device moves again. So there is no need to stop the updates. The problem with stopping them is, if the app gets terminated while the location updates are not active, then it would never get launched again once the device starts moving. »* Le même ingénieur déconseille de chercher à masquer l'indicateur bleu.
- iOS 18 ajoute `diagnostics` (propriétés `authorizationDenied`, `insufficientlyInUse`, `serviceSessionRequired`…) sur la session ([Diagnostic](https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession-3mzv3/diagnostic)). Indisponible avec la cible 17.0 sans `#available`.

---

## 2. Autorisation, indicateur et `Info.plist`

- « Lorsque l'app est active » suffit pour suivre une séance en arrière-plan **si** le suivi a démarré au premier plan et qu'une session d'arrière-plan (ou une Live Activity) est active : *« If you enable background location updates, an app with When in Use authorization continues to run in the background when location services are active »* ([Requesting authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)). WWDC24 : Core Location ne livre pas de mises à jour à une app *« having .whenInUse authorization, and being backgrounded without a LiveActivity or CLBackgroundActivitySession in effect »*.
- « Toujours » n'apporte que le relancement automatique pour certains services (changement significatif, visites, régions) : tableau *« Launches a terminated app automatically — When in Use: No. […] Always: Yes for significant location change, visits, and region monitoring services; no for others »*. Le suivi continu d'une séance n'en fait pas partie. Le relancement décrit au §1.3 est propre à `liveUpdates`.
- Démarrer en arrière-plan échoue : *« Attempts to start location updates while your app runs in the background will fail »* ([`requestWhenInUseAuthorization()`](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization())). Le démarrage d'une Recording doit donc se faire au premier plan.
- **Indicateur bleu** : avec « Lorsque l'app est active », *« the system changes the appearance of the status bar when the app uses location services in the background »* ; `showsBackgroundLocationIndicator` ne concerne que « Toujours » ([doc](https://developer.apple.com/documentation/corelocation/cllocationmanager/showsbackgroundlocationindicator)). WWDC23 : l'indicateur *« keeps the app effectively in-use »*. Toucher l'indicateur ramène dans l'app.
- **« Autoriser une fois »** : autorisation temporaire qui *« expires when the app is no longer in use »* ([`requestWhenInUseAuthorization()`](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization())). Tant que l'indicateur garde l'app « en usage », elle reste valable ; elle revient à « non déterminé » ensuite.
- **Position approximative** : WWDC24 : *« .accuracyLimited as approximate location is updated only every 15 to 20 minutes »*, inutilisable pour une trace. Une demande ponctuelle de précision complète existe : [`requestTemporaryFullAccuracyAuthorization(withPurposeKey:)`](https://developer.apple.com/documentation/corelocation/cllocationmanager/requesttemporaryfullaccuracyauthorization(withpurposekey:completion:)) avec la clé `NSLocationTemporaryUsageDescriptionDictionary`. Son expiration *« is postponed […] while a Continuous Background Location session is active with the background location indicator enabled. This approach […] allows apps to provide experiences that require full accuracy, such as fitness and navigation apps »*. Elle échoue si l'app est en arrière-plan.
- **Autorisation implicite** : *« Core Location sets When in Use authorization implicitly when you process events from CLMonitor, CLLocationUpdate, or use a CLBackgroundActivitySession »*, sauf si `NSLocationRequireExplicitServiceSession` est dans l'`Info.plist` ([Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)). `CLServiceSession` (déclaration explicite des besoins d'autorisation, avec diagnostics) est **iOS 18+** ([doc](https://developer.apple.com/documentation/corelocation/clservicesession-pt7n)).

**Clés `Info.plist` requises** ([Requesting authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)) :

| Clé | Requise quand | Projet (`apps/mobile/project.yml`) |
|---|---|---|
| `UIBackgroundModes` = `location` | suivi en arrière-plan | présente |
| `NSLocationWhenInUseUsageDescription` | toute demande | présente : « … y compris écran verrouillé. » |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | demande « Toujours » | absente (ADR-027 §5 la reporte) |
| `NSLocationTemporaryUsageDescriptionDictionary` | demande de précision complète temporaire | absente |
| `NSMotionUsageDescription` | tout usage de `CMMotionActivityManager` (*« your app crashes when you call this API »* sans elle) | absente |

---

## 3. Signaux pour détecter un arrêt

| Signal | Disponibilité | Ce qu'il dit | Limites documentées |
|---|---|---|---|
| [`CLLocationUpdate.isStationary`](https://developer.apple.com/documentation/corelocation/cllocationupdate/isstationary) | iOS 17 | *« If Core Location stops delivering updates because the device is stationary, then it sets isStationary to true »* | Délai avant la pause non documenté (*« a sufficient amount of time »*). Ne dit rien de la reprise avant la mise à jour suivante. |
| [`CLLocationUpdate.stationary`](https://developer.apple.com/documentation/corelocation/cllocationupdate/stationary) | iOS 18 | WWDC24 : *« true on the last update before updates are paused because the device has stopped moving »* | Même délai inconnu. iOS 18 ajoute aussi `locationUnavailable`, `accuracyLimited`, `authorizationDenied`, `insufficientlyInUse`… |
| [`CLLocation.speed`](https://developer.apple.com/documentation/corelocation/cllocation/speed) + [`speedAccuracy`](https://developer.apple.com/documentation/corelocation/cllocation/speedaccuracy) | iOS 2 / 10 | Vitesse instantanée en m/s ; négative = invalide ; `speedAccuracy` négative = vitesse invalide | Apple : *« use this property for informational purposes only »*. À l'arrêt, la vitesse GPS ne tombe pas forcément à zéro. |
| [`CMMotionActivityManager`](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager) / [`CMMotionActivity`](https://developer.apple.com/documentation/coremotion/cmmotionactivity) | iOS 7 | `stationary`, `walking`, `running`, `cycling`, `automotive`, `unknown`, et `confidence` | Propriétés non exclusives (*« driving in a car and the car stopped at a red light […] both the automotive and stationary properties set to true »*). *« The handler block is executed on a best effort basis and updates are not delivered while your app is suspended »* : seule la dernière valeur arrive au réveil. Exige `NSMotionUsageDescription`. |

**Conséquence documentée** : quand `liveUpdates` met en pause, l'app peut être suspendue (WWDC23 : *« your app might transition from the background running state to the suspended state […] due to automatic pause, because of a stationary device »*). Un minuteur applicatif ne tourne pas pendant ce temps. Toute durée de pause doit donc être calculée à partir des horodatages des points, pas d'un minuteur. Et Core Motion ne livre rien non plus tant que l'app est suspendue.

**Effet sur la Live Activity** : WWDC24 : *« Core Location does not take measures to keep apps running continuously when it has nothing to deliver to them »*. Pendant un arrêt (pause automatique de `liveUpdates`, ou GPS sans fix), l'app peut donc être suspendue : elle ne peut plus pousser de mise à jour à sa Live Activity, qui reste **figée** sur ses dernières valeurs jusqu'à la reprise des points. Il en va de même si l'app arrêtait elle-même le flux pendant une pause manuelle, avec en plus le risque de ne jamais être relancée (§1.4). Ce que la Live Activity peut afficher sans l'app (chrono rendu par le système, état « en pause ») relève de [#45](https://github.com/echimine/clone-strava/issues/45).

---

## 4. Ce que fait Strava

### 4.1 Aide Strava (actuelle)

- iOS, [« How to Use Auto-Pause on iOS »](https://support.strava.com/hc/en-us/articles/216917437-Auto-Pause) : *« Auto Pause for cycling uses GPS movement to automatically detect when you are at rest »*, *« Auto Pause for running is motion-based and uses your accelerometer »*, *« Cycling Auto Pause will be on by default but can be turned off on your settings page »*, et pour le vélo *« the app will only pause when you're completely stopped »*. Aucun seuil publié. Réglage par sport : course, vélo, les deux ou aucun.
- [« How to fix autopause issues »](https://support.strava.com/en-us/articles/15401874-how-to-fix-autopause-issues) : *« If recording a walk or hike, we recommend disabling autopause »* parce que *« The slower speeds often cause the app to pause frequently and have trouble resuming »*. En intérieur ou sans signal, la Recording peut reprendre à tort ; Strava conseille la pause manuelle. Certains téléphones coupent le GPS pendant un long arrêt, et l'ouverture de l'écran d'enregistrement le réactive.
- [« Moving Time, Speed and Pace Calculations »](https://support.strava.com/en-us/articles/15401804-moving-time-speed-and-pace-calculations) : *« Strava relies on a speed threshold to determine whether or not you are resting »* (seuil non publié) ; *« As long as your device records conventional pauses, Strava will respect any pauses in the file »* ; *« If there are any pause events in your activity file, our server will not remove any additional resting time. »* Une pause manuelle se reprend manuellement, même avec la pause automatique activée.

### 4.2 Billet d'ingénierie (Jay Harris, 16 décembre 2014)

[« Improved Auto-pause for Everyone »](https://web.archive.org/web/20150107210154/http://engineering.strava.com/improved-auto-pause-for-everyone/) (l'URL d'origine redirige vers une page 404 de labs.strava.com ; lu via la Wayback Machine). **Daté de 2014** : les principes sont confirmés par l'aide actuelle (GPS pour le vélo, accéléromètre pour la course), pas les chiffres.

**Vélo (GPS)** :
- Serveur : *« looks for portions of the activity where the athlete was moving below a certain speed threshold for more than 15 seconds and removes that time as "resting time" »*.
- Téléphone : *« we detect whether the phone is moving by looking at whether we have received a location update with a positive speed in the last 10 seconds. If we have gone more than 10 seconds without a location update, we auto-pause the app. »* La raison : *« iOS and Android only send these updates reliably when the phone is moving »*.
- Pas de retour en arrière : un arrêt de 25 s ne retire que les 15 s après la pause.
- Reprise : *« as soon as the phone reports a location that 1) is a certain minimum distance away from the location where it paused and 2) indicates that the athlete is moving faster than a certain minimum speed »*.
- Philosophie : *« the app pauses slowly and resumes quickly »* ; les arrêts de quelques secondes aux feux ne sont pas forcément détectés.
- **Dérive et tunnels** : *« the straight-line distance between the last moving point before pausing and the first moving point after resuming is included in the activity »*, donc la distance traversée dans un tunnel est comptée et *« if the GPS wanders around a little while the athlete is stationary, the activity will not include that wandering distance »*.

**Course (accéléromètre)** :
- La version GPS était trop lente : *« pausing sometimes took 5 seconds or more of standing still »* ; plus sensible, elle *« would sometime pause while running or resume while standing still »*.
- Algorithme sur *« changes in the time-averaged jerk »*, pause et reprise *« within about a second »*.
- Courir sur place au feu ne met pas en pause ; perdre le GPS en courant non plus.
- Ne reprend **qu'en courant**, pas en marchant.
- Téléphone tenu immobile en main : pause à tort, corrigée par *« a back-up resume function that will resume the app again within a few seconds based on GPS data »*.
- Avec la pause automatique, *« the server now skips all post-processing »* : les stats affichées en fin d'activité sont celles publiées.
- L'accéléromètre n'a pas été retenu pour le vélo : *« separating noise from signal in that case turned out to be quite difficult »*.

**Note** : Strava a écrit son propre traitement de l'accéléromètre. Core Motion (`CMMotionActivityManager`) expose une classification déjà faite par le système, dont la latence n'est pas documentée par Apple.

---

## 5. Batterie

- Apple ne publie **aucun chiffre** de consommation pour les configurations ci-dessus.
- [Energy Efficiency Guide for iOS Apps, Location](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html) (archive, mise à jour 2016) : *« Requesting higher accuracy than you need causes Core Location to power up additional hardware and waste power »* ; *« Make sure the location manager object's pausesLocationUpdatesAutomatically property is set to YES to help conserve power »* ; *« Set the activityType property […] for example, if your app is performing fitness tracking »* ; *« improper or unnecessary use of location can prevent the device from sleeping, keep location hardware powered up, drain the user's battery »*.
- WWDC23 présente la pause/reprise automatique de `liveUpdates` comme le levier batterie de la nouvelle API (*« contributes to battery life by automatically pausing and resuming the updates »*).
- `liveUpdates` ne permet pas de baisser la précision ni d'espacer les points : le coût se règle par la `LiveConfiguration` et en arrêtant le flux à la fin de la Recording. L'astuce que suggère la doc de `pausesLocationUpdatesAutomatically` (passer à `kCLLocationAccuracyThreeKilometers` en arrière-plan) ne vaut que pour `CLLocationManager` et serait de toute façon incompatible avec une trace.
- `.fitness` désactive le positionnement intérieur.
- iOS 16+ affiche un indicateur dans le Centre de contrôle pour les apps qui suivent activement la position ([`requestWhenInUseAuthorization()`](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization())).

Un chiffrage réel (pourcentage par heure, `.fitness` contre `.otherNavigation`, avec ou sans Core Motion) demande une mesure sur appareil avec Instruments (Energy Log).

---

## 6. Ce que fait le code actuel et ce qu'il faudra adapter

Lu à `b35c7a2`.

| Élément | Aujourd'hui | Écart par rapport aux faits ci-dessus |
|---|---|---|
| Cible | `IPHONEOS_DEPLOYMENT_TARGET: "17.0"` (`project.yml`) | `stationary`, les diagnostics de `CLLocationUpdate` et de la session, et `CLServiceSession` sont iOS 18+ : `#available` ou relèvement de la cible. |
| `Info.plist` | `UIBackgroundModes: [location]`, `NSLocationWhenInUseUsageDescription` | Suffisant pour le GPS en arrière-plan. Manque `NSMotionUsageDescription` si Core Motion est retenu, et `NSLocationTemporaryUsageDescriptionDictionary` si on gère la position approximative. |
| `CoreLocationProvider.startUpdates()` | `liveUpdates(.fitness)`, `guard let location = update.location else { continue }` | Les mises à jour sans position sont jetées, et `isStationary` n'est jamais lu : `LocationSample` ne porte ni l'immobilité ni les diagnostics. |
| Erreurs | `catch { // TODO: expose Core Location errors }` | Si la séquence lève une erreur, le flux s'arrête sans que la Recording le sache. |
| `LocationSample` | coordonnée, altitude, `horizontalAccuracy`, `course`, horodatage | Pas de `speed`/`speedAccuracy`, alors que le contrat de trace a un `speedMs` optionnel et que la vitesse est un signal de pause. |
| `beginBackgroundTracking()` | crée `CLBackgroundActivitySession` | Correct (appelé au démarrage, donc au premier plan). Aucun code ne la **recrée au relancement**. |
| Point d'entrée | `StravaCloneApp` sans `@UIApplicationDelegateAdaptor` ni `didFinishLaunchingWithOptions` | Le montage Apple du §1.3 manque : au relancement en arrière-plan, rien ne relance `liveUpdates` ni ne rejoint la session dans les quelques secondes allouées. |
| Persistance | `GRDBRecordingRepository` : `create`, `append`, `finish` sont des `TODO` | Au lancement, l'app ne peut pas savoir qu'une Recording était en cours ni reprendre ses points. C'est le sujet de [#52](https://github.com/echimine/clone-strava/issues/52). |
| `LocationBroadcaster` | `AsyncStream` par abonné, `.bufferingNewest(16)`, rejoue la dernière valeur à un nouvel abonné | (a) Si `RecordingService` (actor + écriture GRDB par point) prend plus de 16 points de retard, les plus anciens sont **perdus sans signal**. (b) Un nouvel abonné reçoit la dernière position connue, potentiellement ancienne : la Recording pourrait l'enregistrer comme premier point. (c) Le GPS s'arrête quand le dernier abonné part ; au relancement, il faut un abonné (la Recording) avant que la carte n'existe. |
| `RecordingService.record` | ajoute chaque point à la distance, `try?` sur l'écriture | Aucune notion de pause : la dérive GPS à l'arrêt s'ajoute à la distance provisoire. |
| `ActiveRecording.append` | ignore les points de précision > 50 m | Seul filtre existant. |
| `RecordingView` | `requestWhenInUseIfNeeded()` puis `start()` dans la foulée | Si l'autorisation n'est pas encore déterminée, la Recording démarre pendant l'invite. |
| Contrat de trace v1 (`packages/contracts/src/activities/trace.ts`) | points horodatés, aucun champ de pause | Pas de moyen de transmettre une pause au serveur (sujet de [#46](https://github.com/echimine/clone-strava/issues/46)). |
| `computeMetrics` (`packages/core/src/activities/domain/compute-metrics.ts`) | temps en mouvement = segments à ≥ 0,5 m/s ; distance = longueur de toute la trace | La dérive à l'arrêt compte dans la distance ; aucune pause n'est respectée (sujet de [#46](https://github.com/echimine/clone-strava/issues/46)). |

---

## 7. Recommandation de la recherche

Ce que les sources soutiennent, sans trancher les choix produit du §8 :

1. **Garder `liveUpdates` + `CLBackgroundActivitySession`** et l'autorisation « Lorsque l'app est active ». Ne pas demander « Toujours » : rien dans le besoin ne l'exige. **Garder la session même avec une Live Activity** : WWDC23 dit que la Live Activity suffit, mais un rapport de 2025 sans réponse d'Apple dit le contraire, alors que la session marche dans les deux versions. La session reste ouverte de Démarrer jusqu'à Enregistrer/Supprimer, pauses comprises ; `liveUpdates` n'est pas arrêté pendant une pause, manuelle ou automatique : la pause est un état de la Recording, pas du GPS.
2. **Ajouter le montage de relancement** documenté par Apple : `AppDelegate` via `@UIApplicationDelegateAdaptor`, qui lit l'état « Recording en cours » persisté et, immédiatement, recrée la session et la boucle `liveUpdates`. Cela suppose que la Recording soit persistée dès son démarrage (#52).
3. **Faire remonter `isStationary` (et, sous iOS 18, `stationary` et les diagnostics)** dans le type livré par le `LocationProvider`, avec `speed`/`speedAccuracy`, au lieu de jeter les mises à jour sans position. Exposer aussi les erreurs.
4. **Ne pas perdre de points dans le broadcaster** pour l'abonné Recording (tampon non borné ou politique dédiée), et ignorer pour la trace la valeur rejouée si elle est antérieure au démarrage.
5. **Pause automatique fondée sur les horodatages des points**, pas sur un minuteur, puisque l'app peut être suspendue pendant l'arrêt. Le modèle Strava vélo (pause après ~10 s sans point en mouvement, reprise à distance et vitesse minimales, ligne droite pendant la pause) se transpose directement sur la vitesse GPS et `isStationary`. Pour la course, Strava utilise l'accéléromètre parce que le GPS est trop lent ; Core Motion est l'équivalent système, à évaluer sur appareil.
6. **Mesurer sur appareil** avant de figer les seuils : délai réel de `isStationary` en `.fitness`, latence de `CMMotionActivity` à l'arrêt et à la reprise, comportement après fermeture par le sélecteur d'apps, coût batterie par heure.

---

## 8. Décisions ouvertes

Renvoyées aux tickets de la carte #43 (à trancher, pas des faits) :

- **[#46](https://github.com/echimine/clone-strava/issues/46) Représentation des pauses dans la trace et calcul serveur** :
  - comment la trace v1 transmet une pause (événements pause/reprise, segments, drapeau par point) et si l'on passe en `schemaVersion` 2 ;
  - si le serveur respecte les pauses de l'app et cesse alors de retirer le temps de repos (comportement Strava), ou recalcule toujours ;
  - distance pendant une pause : ligne droite entre le dernier point avant et le premier après (Strava), ou points ignorés ;
  - envoi des points enregistrés pendant une pause (gardés pour la carte, exclus du calcul) ou non.
- **[#52](https://github.com/echimine/clone-strava/issues/52) Persistance et reprise d'une Recording** :
  - ce qui est persisté pour savoir au lancement qu'une Recording est en cours (ligne GRDB `recording`, drapeau) et qui recrée la session et `liveUpdates` dans `didFinishLaunchingWithOptions` ;
  - comportement si l'athlète ferme l'app depuis le sélecteur : reprise silencieuse, invite à la reprise, ou fin de la Recording ;
  - politique de tampon du `LocationBroadcaster` pour la Recording et traitement de la valeur rejouée ;
  - cycle de vie de la session : créée à Démarrer, jamais invalidée avant Enregistrer/Supprimer (sinon pas de reprise possible en arrière-plan).
- **[#47](https://github.com/echimine/clone-strava/issues/47) Stats affichées selon le sport** et **[#48](https://github.com/echimine/clone-strava/issues/48) Parcours de démarrage** : quelle `LiveConfiguration` par sport (`.fitness` partout, ou `.otherNavigation` pour certains) ; demande d'autorisation avant le bouton Démarrer ; conduite si la position est approximative ou si l'autorisation est « Autoriser une fois ».
- **[#45](https://github.com/echimine/clone-strava/issues/45) Live Activity** : la Live Activity s'ajoute à `CLBackgroundActivitySession` (recommandation ci-dessus) ou la remplace (WWDC23, contredit par le forum 788647) ; ce qu'elle affiche quand l'app est suspendue pendant un arrêt (chrono rendu par le système, état « en pause »), puisqu'elle ne peut pas être mise à jour pendant ce temps.
- **Nouvelle décision, sans ticket à ce jour** — *Règles de la pause automatique* : sports concernés et valeur par défaut (Strava : vélo activé par défaut, conseil de couper pour marche et randonnée), signal par sport (vitesse GPS + `isStationary` pour le vélo, Core Motion pour la course ou non, donc `NSMotionUsageDescription` et une invite de plus), seuils (délai avant pause, distance et vitesse de reprise), réglage exposé à l'athlète ou non, et cible iOS 17 ou 18.
