# Natation en piscine : données disponibles pour des Records

Recherche pour le ticket [#227](https://github.com/echimine/clone-strava/issues/227) de la carte [#223](https://github.com/echimine/clone-strava/issues/223) « Segments et Records dans l'app ». Date : 2026-11-05.

**Question.** De quelles données dispose-t-on pour tirer des Records (meilleur temps sur 50 m, 100 m, 400 m…) d'une natation en piscine ? Comment une Activité de natation arrive-t-elle dans Nervo, et que contient-elle ?

**Réponse courte.** Aujourd'hui, aucune natation en piscine n'arrive dans Nervo. L'import refuse tout fichier sans position (`no_gps_data`), l'Enregistrement ne propose pas `swim` et la saisie manuelle n'existe pas. Les seules Activités `swim` possibles ont une trace GPS : de l'eau libre importée, ou une Activité GPS dont l'athlète a changé le sport.

La seule source exploitable pour un Record en piscine est le **fichier FIT** :

- les messages `length` donnent, pour chaque longueur, son début, sa durée et son type (actif ou repos) ;
- `session.pool_length` donne la longueur du bassin.

Un Record en piscine est donc faisable, mais **seulement sur des Activités importées en FIT**. Il faut d'abord accepter les fichiers sans GPS pour `swim`, puis extraire et stocker les longueurs. Les distances possibles sont des multiples de la longueur du bassin. TCX, GPX, l'Enregistrement sur l'iPhone et une saisie manuelle ne fournissent pas ces données.

---

## 1. Comment une Activité de natation arrive dans Nervo aujourd'hui (code)

### 1.1 Le sport `swim`

Il est défini dans `packages/db/drizzle/0002_seed_sport_types.sql` :

```sql
('swim', 'water', 'figure.pool.swim', true, false, false, 'pace', 60, 50, 3, true),
```

Cette ligne donne `tracks_distance = true`, `tracks_elevation = false`, `uses_gps = false`, `min_duration_s = 60` et `min_distance_m = 50`. Aucune colonne ni table ne stocke de longueur de bassin, de longueurs, de nage ou de nombre de mouvements.

### 1.2 Import de fichiers (ADR-028) : une natation en piscine est refusée

- **Le parseur FIT** (`packages/track-files/src/fit.ts`) ne lit que `messages.recordMesgs` et `messages.sessionMesgs?.[0]`, dont il garde `startTime`, `totalElapsedTime`, `sport` et `subSport`. Il ignore les tableaux `lengthMesgs` et `lapMesgs`, et les champs `poolLength` et `numActiveLengths`, alors que `@garmin/fitsdk` les décode. Un `record` sans `positionLat`/`positionLong` est seulement compté (`pointsWithoutPosition`).
- **Le type de sortie** `ParsedTrackFile` (`packages/track-files/src/types.ts`) ne contient que `points` (avec latitude et longitude obligatoires), `pointsWithoutPosition`, `name`, `sport`, `startedAtMs` et `endedAtMs`. Il n'a ni tours ni longueurs.
- **La règle de refus** est dans `packages/core/src/activities/domain/import/to-import-trace.ts` :

  ```ts
  if (parsed.points.length === 0) {
    return { ok: false, code: parsed.pointsWithoutPosition > 0 ? "no_gps_data" : "empty_track" };
  }
  ```

  Une natation en piscine n'a aucun point positionné, donc elle échoue en `no_gps_data` (ou en `empty_track`).
- **La décision** vient de l'ADR-028, ligne 195 : « **Indoor files without GPS** (treadmill, home trainer): not supported in the MVP, permanent failure `no_gps_data`. Supporting them needs an activity without `activity_track`, to be specified with indoor recording. »
- **La correspondance des sports** (`packages/core/src/activities/domain/import/sport-mapping.ts`) envoie `swimming`, `swim` et `open_water_swimming` vers `swim`. Pour un FIT `sport:sub_sport`, c'est le sport principal qui décide : `swimming:lapswimming` et `swimming:openwater` donnent tous les deux `swim`. La distinction entre piscine et eau libre est perdue.
- **Le commentaire de `import-activity-from-file.use-case.ts`** (l. 113-114) dit : « distance when it comes from GPS (a pool swim file has none) ». En pratique, ce code n'est jamais atteint pour une piscine, puisque `toImportTrace` a déjà échoué. Le contrôle de distance minimale ne s'applique que si `sport.usesGps` (l. 126).
- **Les formats TCX et GPX** (`tcx.ts`, `gpx.ts`) ne lisent que des `Trackpoint` et des `trkpt` positionnés. Ils ont la même limite.

### 1.3 Trace stockée

La trace est définie dans `packages/contracts/src/activities/trace.ts` (`TRACE_SCHEMA_VERSION = 2`). Elle contient `points[]` (`timestampMs`, `lat` et `lon` obligatoires, puis altitude, vitesse, fréquence cardiaque et cadence en option) et `pauses[]`. Rien n'y représente une longueur, un tour, une nage ou un bassin.

### 1.4 Enregistrement sur l'iPhone (ADR-031) : pas de natation

- `apps/mobile/StravaClone/Features/Recording/Domain/RecordingSport.swift` dit : « Sports a Recording can be made for (ADR-031 §1): the sports with GPS » et déclare `case run, ride, walk, hike`.
- L'ADR-031, ligne 44, le confirme : « `swim` and `other` have no GPS and are out of scope. »
- L'app ne contient aucune référence à HealthKit : aucun `HKWorkout` ni `HKHealthStore` dans `apps/mobile`.

### 1.5 Saisie manuelle : prévue dans le schéma, absente du produit

- L'enum `activity_source` contient `'manual'` (`packages/db/drizzle/0004_activity_import.sql`).
- En revanche, `create-activity.use-case.ts` écrit toujours `source: "recorded"`, et l'app envoie toujours `isManual: false` (`apps/mobile/StravaClone/Core/LocalActivities/APIActivityServer.swift:34`).
- Le recalcul traite une entrée manuelle comme une trace vide (`reprocess-activity.use-case.ts`, l. 98).
- Même si elle existait, une saisie manuelle ne donnerait qu'une distance et une durée totales : aucun découpage par longueur.

### 1.6 Les seules Activités `swim` possibles aujourd'hui

1. **Un fichier de natation en eau libre avec GPS** (FIT `swimming:openwater`, TCX ou GPX avec positions). Sa distance est calculée à partir des positions, avec une vitesse plausible maximale de 5 m/s pour `swim` (`clean-trace.ts`).
2. **Une Activité GPS dont l'athlète change le sport en `swim`.** La distance minimale n'est pas opposée à un sport sans GPS (`update-activity.use-case.ts:138` ; test « does not hold the distance against a sport without GPS » dans `apps/api/src/activities/update-activity.spec.ts`).

---

## 2. FIT : ce que contient un fichier de natation en piscine

Source principale : le profil FIT tel que publié dans `@garmin/fitsdk` 21.217.0, la version installée ici ([`src/profile.js`](https://github.com/garmin/fit-javascript-sdk/blob/main/src/profile.js)), et le [cookbook « Encoding Activity Files »](https://developer.garmin.com/fit/articles/cookbook/encoding_activity_files.html) de Garmin.

### 2.1 Message `length` (n° 101, clé `lengthMesgs`)

- **Champs :**
  - `messageIndex`, `timestamp`, `event`, `eventType`, `startTime` ;
  - `totalElapsedTime` (uint32, `scale: 1000`, « s ») et `totalTimerTime` (idem) ;
  - `totalStrokes` (« strokes »), `avgSpeed` (« m/s »), `swimStroke`, `avgSwimmingCadence` (« strokes/min »), `totalCalories` ;
  - `lengthType`.
- **Aucun champ de distance.**
- **Enum `lengthType`** (profile.js) :

  ```js
  lengthType: {
      0: "idle", // Rest period. Length with no strokes
      1: "active", // Length with strokes.
  },
  ```

- **Enum `swimStroke`** : `freestyle`, `backstroke`, `breaststroke`, `butterfly`, `drill`, `mixed`, `im`, `imByRound`, `rimo`.
- **Ce que dit le cookbook :**
  - « Length messages are used to store the start time, elapsed time, stroke count, and stroke type for each length… »
  - « An idle Length message is used to record rest periods between active sets. »
  - « The length of the pool is a constant and is stored in the Session message. »
  - « It is implied that the distance represented by each Length message is the value of the pool_length field in the Session message. »
- **Ce que dit la page [Activity File](https://developer.garmin.com/fit/articles/file-types/activity.html) :** « The Length Type field is also required for all Length messages. »

### 2.2 Message `lap` (clé `lapMesgs`)

- **Champs :** `numLengths` (« # of lengths of swim pool »), `firstLengthIndex`, `numActiveLengths` (« # of active lengths of swim pool »), `swimStroke`, `subSport`.
- **Cookbook :** « Lap messages are used to group sets of active and idle Length messages. »

### 2.3 Message `session` (clé `sessionMesgs`)

- **Champs :**
  - `poolLength` (n° 44, uint16, `scale: 100`, unité « m ») ;
  - `poolLengthUnit` (type `displayMeasure` : `metric`, `statute` ou `nautical`) ;
  - `numLengths` et `numActiveLengths` (n° 33 et 47) ;
  - `swimStroke`.
- **Cookbook :** « The pool length should be specified in meters, with the pool_length_unit field providing the corresponding units ». Un bassin de 25 yards est donc stocké à 22,86 m, avec `poolLengthUnit = statute`.
- **Enums :** `sport` `5: "swimming"` ; `subSport` `17: "lapSwimming"` et `18: "openWater"`. C'est ce qui distingue piscine et eau libre.

### 2.4 Mises en garde du cookbook

- « Activity files for pool swim activities are interpreted differently by each platform that consumes FIT files. »
- « …it is a best practice to pair a Record message with each Length message. »

Ces `record` n'ont pas de position. C'est pour cela que l'import actuel échoue en `no_gps_data` plutôt qu'en `empty_track`.

### 2.5 Ce que `@garmin/fitsdk` expose

- **Clé par type de message.** `decoder.js` range chaque message sous `messagesKey` : « `this.#messages[messageProfile.messagesKey] = [];` ». On obtient donc directement `messages.lengthMesgs`, `messages.lapMesgs` et `messages.sessionMesgs`, avec des noms de champs en camelCase.
- **Options du README** ([fit-javascript-sdk](https://github.com/garmin/fit-javascript-sdk/blob/main/README.md)) : « All options are enabled by default. »
  - `convertTypesToStrings` : « When true field values are converted from raw integer values to the corresponding string values as defined in the FIT Profile. » On obtient `lengthType: "active" | "idle"`, `subSport: "lapSwimming"` et `poolLengthUnit: "metric" | "statute"`.
  - `applyScaleAndOffset` : « the scale and offset values as defined in the FIT Profile are applied to the raw field values ». On obtient `totalElapsedTime` en secondes décimales et `poolLength` en mètres.
- **Côté Nervo.** `fit.ts` appelle déjà `decoder.read` avec `applyScaleAndOffset`, `convertDateTimesToDates`, `expandComponents` et `expandSubFields`. `convertTypesToStrings` reste à sa valeur par défaut, `true`. **Aucune dépendance n'est à ajouter** : il suffit de lire `lengthMesgs` et `sessionMesgs[0].poolLength`.

---

## 3. TCX : pas de natation, pas de longueur

Source : [TrainingCenterDatabase v2 XSD](https://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd).

- `Sport_t` n'énumère que `Running`, `Biking` et `Other`.
- `ActivityLap_t` contient `TotalTimeSeconds`, `DistanceMeters`, `Calories`, `Intensity`, `TriggerMethod` et `Track`, plus des `Extensions`. Il n'y a ni longueur de bassin, ni longueur, ni nage.

Une natation en piscine exportée en TCX est au mieux un `Other` découpé en tours de distance arbitraire. Elle ne permet pas de Record fiable.

GPX n'a pas non plus de notion de tour ni de longueur, seulement des `trkpt` positionnés. C'est déjà la base du parseur actuel.

---

## 4. HealthKit (si l'app lit un jour Apple Santé)

Source : la documentation Apple developer (HealthKit).

- **`HKWorkoutActivityType.swimming`** : « The constant for swimming. »
- **`HKMetadataKeySwimmingLocationType`** : « Set this key on a workout object that represents swimming… » Ses valeurs `HKWorkoutSwimmingLocationType` sont `.pool` (« The user swam in a pool. »), `.openWater` et `.unknown`.
- **`HKMetadataKeyLapLength`** : « A key that indicates the length of a lap during a workout. » / « Set this key on a workout, workout segment, or a quantity sample that represents distance. »
- **`HKWorkoutEventType.lap`** :
  - « Lap events partition a workout into segments of equal distance (for example, laps around a track or laps in a pool)… Lap events can't overlap. »
  - « Newer lap events use the date interval to mark the start and the duration of the lap… they do not need to fill the workout; however, you should ideally mark any rest periods between laps using pause and resume events. »
- **`HKWorkoutEventType.segment`** : « when swimming, you can use segments to group consecutive laps with the same style of stroke. » / « Unlike laps, segments can freely overlap. »
- **`HKMetadataKeySwimmingStrokeStyle`** : « the predominant stroke style for a lap of swimming. » / « Set this key on workout lap events. »
- **`HKQuantityTypeIdentifier.swimmingStrokeCount`** : « the number of strokes performed while swimming ». **`.distanceSwimming`** : « the distance the user has moved while swimming ».
- **`HKWorkoutConfiguration.lapLength` et `.swimmingLocationType`** : la longueur de bassin et le lieu de nage d'une séance.
- **Apple Watch, [guide Pool Swim](https://support.apple.com/en-in/guide/watch/apd5f25bad11/9.0/watchos)** : « The pool swim workout automatically tracks your sets and when you rest. »

**Ce que cela permet.** Une longueur est un événement `.lap` daté, avec un début et une durée. Sa distance est `HKMetadataKeyLapLength`. Le repos est une pause, une reprise ou un trou entre deux longueurs. Il n'existe pas de longueur « au repos » explicite comme en FIT. On pourrait appliquer le même calcul de Record, mais cela demande la lecture d'Apple Santé (un nouveau périmètre) et une Apple Watch.

**Non vérifié dans une source primaire :** qu'un iPhone seul ne puisse pas suivre une natation en piscine. Apple ne documente le suivi Pool Swim que sur l'Apple Watch. Un iPhone n'a de toute façon ni GPS ni capteur utilisable dans l'eau.

---

## 5. Ce que font Strava et Garmin

### 5.1 Strava : aucun meilleur effort en natation documenté

- **[What Are Best Efforts on Strava?](https://support.strava.com/hc/en-us/articles/15401646)** : « See your personal records (PRs) and performance trends in several running and cycling categories with Best Efforts. » / « Best Efforts tracks your fastest times at benchmark running and cycling distances… ». La natation n'y figure pas.
- **[Running Best Efforts](https://support.strava.com/hc/en-us/articles/15401661)** : 400 m, 1 km, ½ mile, 1 mile, 2 miles, 5 km, 10 km, 15 km, 10 miles, 20 km, semi-marathon, 30 km, marathon, 50 km. La page indique que le calcul utilise le temps écoulé (*elapsed time*) plutôt que le temps de déplacement.
- **[Swim Activities on Strava](https://support.strava.com/hc/en-us/articles/206645830-Swim-Activities-on-Strava)** :
  - « You will have to input the pool length before starting your activity. »
  - « Indoor swims on Strava will not display a map; instead, a laps view will be displayed. »
  - « Distance is calculated by adding up the laps' distances »
  - « The Strava app for Apple Watch can record swimming activities but without GPS »
  - Rien sur les meilleurs efforts, les Records ou les Segments en natation.
- **Conclusion :** aucune trace d'un meilleur effort en natation chez Strava, ni en piscine ni en eau libre. Nervo irait plus loin que Strava sur ce point.

### 5.2 Garmin : Records personnels en piscine, à partir des longueurs

- **[Manuel Garmin Swim 2](https://www8.garmin.com/manuals/webhelp/garminswim2/EN-US/Swim_2_OM_EN-US.pdf)** :
  - « Personal records include your fastest time over several typical race distances and longest swim. »
  - « The Garmin Swim 2 device measures and records distance by completed lengths. The pool size must be correct to display accurate distance. »
  - « Length: One trip down the pool. » / « Interval: One or more consecutive lengths. A new interval starts after a rest. »
  - « If you rest for more than 15 seconds, the device automatically creates a rest interval. »
- **Distances retenues par Garmin Connect : non vérifiées dans une source primaire.** La FAQ officielle « [Garmin Connect: Personal Records for Pool Swimming Activities](https://support.garmin.com/en-US/?faq=O8rHgFa3iB2HpErPIxL4v5) » est restée inaccessible (protection Cloudflare). Les forums Garmin citent 100 m, 400 m, 750 m, 1 000 m et 1 500 m, et notent l'absence de 50, 200 et 800 m. L'exclusion de l'eau libre, et le cas d'un bassin de 33⅓ m qui ne tombe pas sur 100 m pile, ne sont rapportés que sur des forums.

---

## 6. Ce qui est faisable pour un Record en piscine dans Nervo

### 6.1 Quelles Activités

| Arrivée | Données utiles à un Record en piscine | Faisable ? |
|---|---|---|
| Import **FIT** `swimming:lapSwimming` | `lengthMesgs` (début, durée, `active`/`idle`, nage, mouvements) et `session.poolLength` | **Oui**, une fois le refus `no_gps_data` levé pour `swim` |
| Import **TCX** | Tours sans longueur ni bassin, sport `Other` | Non |
| Import **GPX** | Points positionnés seulement | Non (et une piscine n'a pas de position) |
| **Enregistrement** sur l'iPhone | `swim` exclu (ADR-031) ; ni GPS ni capteur dans l'eau | Non |
| **Saisie manuelle** | N'existe pas ; ne donnerait qu'un total | Non |
| **Apple Santé** (Apple Watch), non lu aujourd'hui | Événements `.lap` et `HKMetadataKeyLapLength` | Oui en théorie, mais c'est un nouveau périmètre |
| Natation en **eau libre** GPS (FIT `openWater`, GPX) | Points GPS | Possible comme un Record de course, mais le GPS dans l'eau est imprécis. Ni Strava ni Garmin (non vérifié pour Garmin) ne le font : à trancher |

### 6.2 Travaux nécessaires (pour l'ADR-039 et les specs)

1. **Accepter une Activité `swim` sans GPS à l'import.** C'est l'« activity without `activity_track` » que l'ADR-028 l. 195 renvoie à plus tard : ADR-028 à amender. Cela implique :
   - une Activité sans tracé ni carte ;
   - une distance officielle égale à la somme des longueurs actives × `poolLength`, comme chez Strava : « Distance is calculated by adding up the laps' distances » ;
   - un temps de déplacement égal à la somme des durées des longueurs actives.
2. **Étendre `@repo/track-files`.** `ParsedTrackFile` gagne `poolLengthM`, `poolLengthUnit` et `lengths[]` (`startMs`, `elapsedS`, `timerS`, `type: active|idle`, `stroke?`, `strokes?`), lus depuis `lengthMesgs` et `sessionMesgs[0]`. Le sous-sport doit aussi être conservé, pour distinguer la piscine de l'eau libre.
3. **Stocker les longueurs.** Il y a deux options :
   - une trace `schemaVersion: 3` avec `lengths[]` et `poolLengthM` dans le bucket ;
   - une colonne `pool_length_m` sur l'Activité, plus les longueurs dans l'Activity analysis versionnée (`ACTIVITY_ANALYSIS_VERSION`, backfill possible).

   Les fichiers FIT d'origine étant conservés (ADR-028), les natations importées après coup peuvent être recalculées. En revanche, celles refusées avant ce changement devront être réimportées par l'athlète.
4. **Calculer le Record.** C'est la meilleure somme de durées sur une **fenêtre glissante de N longueurs actives consécutives**, avec N × `poolLengthM` égal à la distance visée :
   - Une longueur `idle` coupe la séquence. C'est la lecture naturelle du cookbook (« rest periods between active sets ») et de Garmin (« A new interval starts after a rest ») ; aucune source ne le définit pour les Records.
   - Seules les distances multiples de la longueur du bassin sont calculables. En bassin de 25 m : 50, 100, 200, 400, 800, 1 500 m. En bassin de 50 m : pas de 25 m. En bassin de 33⅓ m : 100 m, mais ni 50 ni 200 m.
   - Un bassin en yards (22,86 m) ne tombe sur aucune distance métrique. Il faut choisir : des Records métriques seulement sur les bassins métriques, ou des distances en yards à part.
5. **Choisir le temps.** Strava utilise le temps écoulé pour ses meilleurs efforts en course. Pour une piscine, la somme des `totalElapsedTime` des N longueurs consécutives est équivalente à « fin de la dernière − début de la première » quand les longueurs se suivent sans trou.

### 6.3 Décisions restant à prendre (grilling)

- Distances de Record en piscine. Garmin, selon les forums : 100, 400, 750, 1 000, 1 500 m. Distances olympiques FINA : 50, 100, 200, 400, 800, 1 500 m.
- Une longueur `idle` coupe-t-elle la séquence ? Recommandé : oui.
- Bassins en yards : distances en yards à part, ou rien ?
- Eau libre GPS : Record ou pas ? Recommandé : pas de Record. Strava n'en fait pas, et le GPS dans l'eau est imprécis.
- Un même Record pour piscine et eau libre, ou deux Records séparés ?
- Lecture d'Apple Santé : hors carte, ou à ajouter pour les nageurs avec Apple Watch ?
