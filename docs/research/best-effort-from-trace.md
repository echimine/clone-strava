# Meilleur temps sur une distance à partir d'une trace

Recherche pour le ticket [#226](https://github.com/echimine/clone-strava/issues/226) de la carte [#223](https://github.com/echimine/clone-strava/issues/223) « Segments et Records dans l'app ». Date : 2026-11-05.

**Question.** Comment calculer le **meilleur temps sur une distance fixe** (Record) à partir de la trace d'une Activité ? Quel algorithme, avec quelle précision ? Que font Strava, Garmin, Runalyze, Golden Cheetah et intervals.icu ? Où le brancher dans Nervo, et combien coûte le recalcul de tout l'historique ?

**Réponse courte.**

- **L'algorithme** est une fenêtre glissante à deux pointeurs sur la distance cumulée, en O(n) par distance. Pour un temps exact, on interpole linéairement le bord de la fenêtre qui tombe entre deux points. La fenêtre peut commencer n'importe où dans l'Activité, pas seulement sur un Split. Mesuré en Node : **0,75 ms** pour 14 distances sur 3 h à 1 Hz (10 800 points), **2,5 ms** sur 8 h. C'est négligeable devant le téléchargement de la trace depuis S3.
- **Strava utilise le temps écoulé**, donc les arrêts comptent dans le temps : « Best Efforts on Strava uses your activity's elapsed time rather than moving time ». Il exclut aussi les passages où le GPS est mauvais. Golden Cheetah compte également le temps écoulé. Pour intervals.icu, seuls des utilisateurs l'affirment.
- **Le branchement naturel est l'Activity analysis** (ADR-036 §6). `computeAnalysis` construit déjà la distance cumulée `alongM` sur la trace nettoyée avant la zone de confidentialité, Pauses comprises. Passer `ACTIVITY_ANALYSIS_VERSION` à 2 recalcule tout l'historique sans code de backfill nouveau, au rythme de 100 Activités par 10 min. Le classement des Records d'un athlète, lui, demande une table interrogeable, pas du `jsonb`.
- **La natation en piscine** ne passe pas par cet algorithme : il faut une fenêtre de N longueurs actives consécutives. Voir [`pool-swim-records.md`](pool-swim-records.md) (#227).

---

## 1. Ce que font les autres

### 1.1 Strava : Best Efforts

**Course à pied.** Source : [Best Efforts (Running)](https://support.strava.com/en-us/articles/15401661-best-efforts-running), article daté du 17 sept. 2026.

- Distances : « 400m, 1K, 1/2 mile, 1 mile, 2 miles, 5K, 10K, 15K, 10 miles, 20K, half marathon, 30K, marathon, and 50k ».
- Temps : « Best Efforts on Strava uses your activity's elapsed time rather than moving time. »
- Source : « Your times are tracked automatically with GPS data from your running activities. »
- Pour chaque Activité : « On every run you upload, you'll also see your fastest marks from that run for every benchmark distance you covered. »
- Correction manuelle : « Click the "Edit Time" box under the result to enter a precise chip time from a race or correct for faulty GPS data. » L'article ajoute : « The GPS data of the activity cannot be altered. »
- Ce qui est conservé : « top three lifetime efforts and top ten annual efforts at each distance ». Et : « If you remove a PR, your next fastest time will become your PR. »

**La fenêtre commence n'importe où.** Source : l'ancien article « Estimated Best Efforts for Running » (216917127), lu sur la [Wayback Machine du 2022-12-02](https://web.archive.org/web/20221202062530/https://support.strava.com/hc/en-us/articles/216917127-Estimated-Best-Efforts-for-Running).

- « A Best Effort for a given distance can be calculated at any point in your activity and is not related to your splits. »
- « Best Efforts use elapsed time, not moving time, similar to a race where the timer would keep running even if you stop. »
- Sur une Activité qui atteint tout juste la distance : « Estimate Best Efforts can be finicky - especially when they barely cover the milestone distance. We suggest running through the milestone you are hoping to achieve. »

**Qualité du GPS et recalcul.** Source : [Troubleshooting Best Efforts](https://support.strava.com/en-us/articles/15402001-troubleshooting-best-efforts).

- « If there are missing points, errant points, or other false accelerations, that part of the activity will not be eligible for a Best Effort. »
- Recalcul : « select the Refresh Stats button underneath your Lifetime totals. If that doesn't help, proceed with submitting a support ticket, and we will refresh your Best Efforts for you. » Le recalcul est donc à la demande. Aucun recalcul automatique après une modification de l'Activité n'est documenté.
- La phrase sur le temps écoulé de cette page vise « running and cycling activities ».

**Vélo.** Source : [Best Efforts (Cycling)](https://support.strava.com/en-us/articles/15401645-best-efforts-cycling).

- Distances : « 5 miles, 10K, 10 miles, 20K, 30K, 40K, 50K, 80K, 50 miles, 90K, 100K, 100 miles, and 180K ».
- S'y ajoutent la puissance sur des durées fixes (5 s à 2 h) et une courbe de puissance, la plus longue sortie, la plus grosse montée et le dénivelé.
- GPS : la puissance « does not need GPS, however, the other best efforts do ».
- Sorties virtuelles : « except for Power, your virtual activities will not count towards any of your other best efforts ».

**API.** Source : [Strava API reference](https://developers.strava.com/docs/reference/).

- `DetailedActivity.best_efforts` est « A collection of DetailedSegmentEffort objects ». Il n'existe pas de modèle `BestEffort` à part.
- Champs utiles : `elapsed_time`, `moving_time`, `distance`, `start_index` (« The start index of this effort in its activity's stream »), `end_index`, et `pr_rank` (« The rank of the effort on the athlete's leaderboard if it belongs in the top 3 at the time of upload »).
- Les bornes sont des indices de points. Strava ne semble donc pas interpoler, mais c'est une déduction : la doc ne le dit pas.

**Non vérifié.** L'existence de Best Efforts en natation (aucun article trouvé), l'interpolation exacte des bords, et un recalcul automatique quand la distance d'une Activité change.

### 1.2 Garmin Connect : Records personnels

La FAQ officielle de support.garmin.com est rendue en JavaScript et **n'a pas pu être lue**. Ce qui suit vient du manuel d'une montre et de textes d'aide Garmin cités sur les forums : c'est une source secondaire.

- [Manuel Forerunner 265](https://www8.garmin.com/manuals/webhelp/GUID-F41EAFB3-6CC9-42DE-9C6C-9E358DBB0671/EN-US/GUID-51F2755C-0909-4C39-9540-B9F4F1D3E156.html) : « When you complete an activity, the watch displays any new personal records you achieved during that activity. » C'est **la montre** qui détecte le Record.
- Texte d'aide cité sur le [forum Garmin](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-iOS/389629/personal-records-don-t-match-distance) : si l'Activité importée « contains no PRs reported by the device », Connect vérifie si la distance totale « meets and barely exceeds the distance of the closest PR distance ». Sinon, « you will need to set the PR manually ».
- Texte d'aide français cité sur le [forum Garmin](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-andriod/217810/personal-records-calculation) : « Connect recherche un record personnel uniquement lors du premier téléchargement d'une activité. »
- Il y a donc deux niveaux : la meilleure fenêtre, calculée par la montre et écrite dans le FIT ; à défaut, Connect prend le temps de l'Activité entière si sa distance est à peine au-dessus de celle du Record.

**Non vérifié.** La liste officielle des distances, et si le temps est le chrono (pauses exclues) ou le temps écoulé.

### 1.3 Runalyze

Le code ouvert n'est plus maintenu (« Discontinued as OpenSource », dernier commit `5669237`, novembre 2019). Il reste la meilleure référence lisible d'un algorithme à interpolation.

- [`inc/core/Calculation/Math/SubSegmentMaximization.php`](https://github.com/Runalyze/Runalyze/blob/5669237a78c7d3512df969052fd0d97e5dca6820/inc/core/Calculation/Math/SubSegmentMaximization.php) : « Find maximal sub-segments of specified lengths with respect to their sum of some given input data. » Pour minimiser un temps : « it's possible to apply a strictly monotonous decreasing function ».
- C'est une fenêtre à deux pointeurs. Quand la fenêtre dépasse la distance visée, sa somme est **remise à l'échelle** au prorata (l. 150-163) :

  ```php
  $overlengthFactor = $this->InterpolateOverlength ? $this->SegmentLengths[$t] / $this->CurrentLength[$t] : 1;
  ```

  Le commentaire en donne un exemple : « An active interpolation will give a maximum of 400 for a length of 10, if a segment of length 15 and value 600 is found only. »
- Distances proposées (`src/CoreBundle/Controller/Activity/ViewController.php`, l. 190) : `[0.2, 1.0, 1.609, 3.0, 5.0, 10.0, 16.09, 21.1, 42.2, 50, 100]` km.
- À l'import GPX, avec la détection de pause activée, les trous de temps trop grands sont retirés (`GpxTrack.php`). Le temps se rapproche alors du temps en mouvement. C'est une lecture du code, non documentée.
- Les « Rekorde » de Runalyze classent des **Activités entières** (`ORDER BY (distance/s) DESC`). L'aide [race-result-suggestions](https://runalyze.com/help/article/race-result-suggestions) exige qu'une Activité soit marquée comme course : « Only then Runalyze can analyze your best times. »

**Non vérifié.** Si runalyze.com promeut aujourd'hui automatiquement les meilleurs tronçons en Records.

### 1.4 Golden Cheetah

Lu au commit `c646897` (4 nov. 2026).

- [`src/Metrics/PeakPace.cpp`](https://github.com/GoldenCheetah/GoldenCheetah/blob/c6468970862d17060160d1d6b37904f20c4acee4/src/Metrics/PeakPace.cpp#L730-L771), l. 730-771 : la classe `BestTime` définit des métriques « Best 50m » à « Best Marathon » (de 50 m à 42,195 km). Elles ne s'appliquent que si une vitesse est présente (`ride->present.contains("S")`) :

  ```cpp
  AddIntervalDialog::findPeaks(item->context, false, item->ride(), spec, RideFile::kph, RideFile::original, meters, 1, results, "", "");
  if (results.count() > 0) secs = results.first().stop - results.first().start;
  ```

- `findPeaks` en mode distance (`src/Gui/AddIntervalDialog.cpp`, l. 846-885) fait glisser une fenêtre sur les points bruts. Une fenêtre compte dès que sa distance est ≥ la cible.
- **Pas d'interpolation** : le temps retenu va d'un point à l'autre, donc la fenêtre peut dépasser un peu la distance.
- Les trous ne sont pas sautés, le temps vient des horodatages : c'est du temps écoulé. Le cache `RideFileCache` remplit aussi les trous d'enregistrement avec des zéros (l. 1287-1294, « fill in any gaps in recording »).

### 1.5 intervals.icu

- Algorithme décrit par son développeur, le 23 mai 2022, sur le [forum](https://forum.intervals.icu/t/best-pace-achievements-for-running-et-al/13029) :
  - il cherche les tronçons « that are >= 5000m (e.g. 5003m) » ;
  - il calcule l'allure sur cette distance réelle ;
  - il « then calculates the seconds for the best effort distance (e.g. 5000m) from that ».

  C'est la même remise à l'échelle que Runalyze.
- Par défaut, l'allure est ajustée à la pente (« Intervals.icu shows gradient adjusted pace by default »). Une option « Ignore pace » retire une Activité des meilleurs efforts.
- API (spec OpenAPI) : `GET /api/v1/activity/{id}/best-efforts` renvoie des `Effort { start_index, end_index, average, duration, distance }`.
- **Temps écoulé ou en mouvement : non confirmé par le développeur.** Seuls des utilisateurs disent que c'est le temps écoulé, Pauses comprises ([forum, mars 2026](https://forum.intervals.icu/t/swim-records-based-on-elapsed-time-separate-pace-zones-by-pool-length/124761)).

### 1.6 Synthèse

| | Fenêtre n'importe où | Temps | Bord de fenêtre | Mauvais GPS |
|---|---|---|---|---|
| **Strava** | Oui (dit explicitement) | Écoulé (dit explicitement) | Indices de points (déduit) | Tronçon exclu |
| **Garmin Connect** | Montre : oui. Serveur : Activité entière | Non vérifié | — | — |
| **Runalyze** | Oui | Écoulé, sauf pauses retirées à l'import | Remise à l'échelle `t × D / d` | — |
| **Golden Cheetah** | Oui | Écoulé | Point à point, sans ajustement | — |
| **intervals.icu** | Oui | Écoulé (selon des utilisateurs) | Remise à l'échelle `t × D / d` | — |

Strava recalcule à la demande (bouton « Refresh Stats » ou ticket) ; Garmin Connect ne cherche qu'au premier import.

---

## 2. L'algorithme

### 2.1 Données

On part de la même entrée que `computeAnalysis` (`packages/core/src/activities/domain/compute-analysis.ts`) :

- `points` : la trace **nettoyée** par `cleanTrace` (précision ≤ 50 m, horodatages strictement croissants, sauts au-dessus de la vitesse plausible du sport supprimés, soit 12 m/s pour `run` et 35 m/s pour `ride`) ;
- `alongM[i]` : la distance cumulée au point `i`, comptée comme la distance officielle. Une jambe qui enjambe une Pause n'ajoute **aucune** distance ;
- `t[i]` : l'horodatage du point `i`.

`alongM` est croissant au sens large, et `t` strictement croissant.

### 2.2 Fenêtre glissante exacte

On cherche, pour une distance `D`, le minimum de `T(x + D) − T(x)` sur toutes les positions de départ `x`, où `T(m)` est l'instant où l'athlète passe à `m` mètres, interpolé linéairement entre deux points.

Entre deux points consécutifs, `T` est affine. La fonction `x ↦ T(x + D) − T(x)` est donc affine par morceaux, et son minimum tombe sur une **cassure** : soit le début de la fenêtre est sur un point, soit sa fin. Il suffit de tester ces deux familles :

1. **Fin sur le point `j`** : début à `alongM[j] − D`, temps de départ interpolé entre les deux points qui l'encadrent.
2. **Début sur le point `i`** : fin à `alongM[i] + D`, temps d'arrivée interpolé.

Chaque famille se parcourt avec deux pointeurs qui n'avancent que vers l'avant. On obtient **O(n) par distance**, O(n × k) pour k distances, et une mémoire O(1) en plus de `alongM`. Le résultat est exact au sens du modèle « vitesse constante entre deux points ».

La remise à l'échelle de Runalyze et d'intervals.icu (`t × D / d` sur la plus courte fenêtre ≥ D qui commence sur un point) est une approximation de la famille 2. Avec des points à 1 Hz, l'écart est inférieur à une seconde.

### 2.3 Mesure

Prototype jetable des deux familles, sur une course simulée à environ 3 m/s, 1 point par seconde, 14 distances (de 400 m à 50 km), Node 24 sur MacBook :

| Trace | Points | Distance | Temps pour 14 distances |
|---|---|---|---|
| 3 h | 10 800 | 32,6 km | 0,75 ms |
| 8 h | 28 800 | 86,5 km | 2,5 ms |

Le calcul est négligeable devant le reste de `compute` : téléchargement S3, décompression, `cleanTrace`, rééchantillonnage pour le dénivelé, géocodage.

### 2.4 Précision et cas limites

- **Points espacés.** C'est le cas des fichiers importés en « smart recording » Garmin, avec un point toutes les quelques secondes. L'interpolation suppose une vitesse constante dans la jambe ; l'erreur est bornée par la durée d'une jambe et reste faible sur 5 km. Sur 400 m, elle compte davantage.
- **Bruit GPS.** Le zigzag d'une trace bruitée **allonge** la distance, donc rend les Records **trop rapides**, surtout sur les courtes distances. `cleanTrace` supprime seulement les sauts au-dessus de la vitesse plausible. Strava va plus loin : un tronçon avec des points manquants ou des « false accelerations » n'est pas éligible. Une règle équivalente reste à décider (voir §4).
- **Trou sans Pause.** Une perte de GPS, ou iOS qui relance l'app en arrière-plan (ADR-031 : « the gap counts as a GPS loss »), donne une jambe longue en temps. Comme le temps est écoulé, ce trou ne rend pas le Record plus rapide. Mais la distance de la jambe est une ligne droite, donc sous-estimée : une fenêtre qui traverse le trou est simplement lente, et ne nuit pas.
- **Activité qui atteint tout juste la distance.** Si la distance officielle est ≥ D, une fenêtre existe et vaut au plus le temps total. C'est cohérent avec la distance affichée, contrairement à l'avertissement de Strava (« finicky »).
- **Arrondi.** Strava affiche des secondes. Stocker des millisecondes, ou des secondes en `real`, permet de départager deux Records sans ex æquo artificiels.

### 2.5 Temps écoulé ou en mouvement

Dans Nervo, une Pause (manuelle ou automatique, ADR-031 §4, §12) n'ajoute aucune distance, mais son temps est dans l'horloge. Trois choix sont possibles pour le temps d'une fenêtre :

| Choix | Ce qu'il fait | Conséquence |
|---|---|---|
| **Écoulé** (Strava, Golden Cheetah) | `T(fin) − T(début)`, Pauses et arrêts compris | Comme une course chronométrée. Un feu rouge ou une Pause ralentit le Record. Cohérent avec Strava. |
| **Hors Pauses** | Écoulé, moins la durée des Pauses comprises dans la fenêtre | Un athlète qui met en pause à chaque feu obtient un Record plus rapide qu'un autre sans auto-pause. L'auto-pause est activée par défaut pour `ride` (ADR-031 §4). |
| **En mouvement** | Somme des jambes au-dessus de 0,5 m/s, comme `movingTimeS` | Encore plus flatteur. Aucune des sources ne le fait pour un Record. |

**Recommandation : le temps écoulé**, comme Strava. Il ne dépend pas du réglage d'auto-pause, il ne peut pas être gonflé par une Pause, et il correspond à l'idée d'un chrono de course.

---

## 3. Où le brancher dans Nervo

### 3.1 Dans le calcul : l'Activity analysis

`OfficialValuesService.compute` (`packages/core/src/activities/services/official-values.ts`) appelle déjà `computeAnalysis(points, { pauses })` sur les points nettoyés, **avant** la zone de confidentialité. C'est le bon endroit :

- `computeAnalysis` construit déjà `alongM` et les jambes, avec la même règle de Pause que la distance officielle. Les Records s'additionnent donc exactement à ce que l'athlète voit.
- La trace avant la zone de confidentialité est la bonne : un Record ne contient que des distances et des temps, pas de coordonnées. L'ADR-036 §6 donne le même argument pour les Splits. Il faut toutefois s'assurer de ne jamais exposer `startM` à un autre athlète si cela permet de situer le domicile, ce qui est peu probable.
- Le calcul tourne dans `process-activity` et dans `reprocess-activity`. Un changement de sport recalcule donc déjà les Records avec le nouveau sport (ADR-033 §5).
- Une suppression d'Activité les supprime par la cascade de `activity_analysis`.

Le résultat par Activité ressemblerait à `bestEfforts: [{ distanceM, elapsedTimeMs, startM }]`, un élément par distance couverte, calculé seulement pour les sports avec GPS. La natation en piscine a son propre calcul (#227).

### 3.2 Dans le stockage : une table, pas du `jsonb`

Le meilleur temps **d'une Activité** peut vivre dans `activity_analysis` à côté des Splits. Mais les questions de la carte portent sur **l'historique d'un athlète** : son Record sur 5 km, son top 3 pour les médailles, son classement à un instant donné. Les poser à du `jsonb` dans `activity_analysis` oblige à parcourir toutes ses Activités.

Une table dédiée, possédée par `activities` (ADR-021 §1), répond à ces questions par un index. Par exemple : `activities.activity_best_effort (activity_id → activity cascade, distance_code, elapsed_time_ms, start_m)`, avec un index sur `(user, sport, distance_code, elapsed_time_ms)`. Elle serait écrite par `save` dans la transaction de traitement, comme `activity_stats`. Le module `segments` n'a pas à la connaître : un Record n'est pas un Effort sur un Segment (cadrage de la carte).

`pr_rank` de Strava est figé « at the time of upload ». Calculer le rang à la lecture est l'autre choix, et il suit les suppressions. C'est à trancher au grilling.

### 3.3 Le recalcul de tout l'historique

Le mécanisme existe déjà (ADR-036 §7) :

- `ACTIVITY_ANALYSIS_VERSION` passe de 1 à 2.
- La boucle de réconciliation (toutes les 10 min) sélectionne jusqu'à **100** Activités `processed` dont la version est inférieure (`ActivityRepository.findWithOutdatedAnalysis`). Elle met en file `reprocess-activity` avec le job id `reprocess-{activityId}-analysis-v2`.
- `ReprocessActivityUseCase` recalcule tout via `compute` dans une transaction, sans événement realtime, puisque le sport n'a pas changé.

Coût :

- **Débit** : 100 Activités par 10 min, soit 600 par heure et 14 400 par jour. Nervo n'ayant jamais été publié, l'historique tient en une passe de quelques heures au plus.
- **Par Activité** : un téléchargement S3 (jusqu'à 50 Mo compressés au maximum, bien moins en pratique), le nettoyage, et tout le reste de `compute`. Le calcul des Records lui-même ajoute environ 1 ms.
- **À surveiller** : `compute` appelle aussi `GeocodingService.reverse` (Mapbox), **sans cache**. Le backfill refait donc un géocodage inverse par Activité. Ce n'est pas un problème au volume actuel, mais il est inutile pour un simple ajout de Records.
- Un job de backfill qui échoue définitivement n'est pas relancé avant la version suivante (ADR-036 §7). C'est acceptable.

Strava ne documente qu'un recalcul à la demande, et Garmin ne cherche qu'au premier import. Le backfill automatique de Nervo va donc au-delà des deux.

---

## 4. Décisions restant à prendre (grilling)

- **Distances par sport.**
  - `run` : la liste de Strava (400 m à 50 km).
  - `ride` : la liste de Strava (8 km à 180 km).
  - `walk` et `hike` : aucune source trouvée. Des Records y ont-ils un sens ?
  - `swim` : voir #227.
- **Temps écoulé** (recommandé) ou hors Pauses.
- **Éligibilité d'un tronçon.** Faut-il exclure les fenêtres qui contiennent un trou sans Pause au-delà de N secondes, ou une accélération improbable, comme Strava ? Recommandation : commencer sans exclusion supplémentaire au-delà de `cleanTrace`, puisque le temps écoulé neutralise déjà les trous. Le plus gros risque restant est le bruit GPS sur 400 m.
- **Interpolation exacte** (recommandée, §2.2) ou bornes sur des points comme Strava. Les bornes sur des points permettent de garder `startIndex`/`endIndex` pour surligner le tronçon sur la carte. L'interpolation peut aussi garder des distances (`startM`).
- **Correction manuelle d'un temps**, comme le « Edit Time » de Strava : dans la carte ou hors carte ?
- **Rang figé à l'import ou calculé à la lecture** : le second suit les suppressions et les changements de sport.
- **Stockage** : table dédiée dans `activities` (recommandée) ou `jsonb` dans `activity_analysis`.
- **Géocodage pendant le backfill** : le garder, ou ne pas le refaire quand seule l'analyse est en retard.

## 5. Sources

- Strava :
  - [Best Efforts (Running)](https://support.strava.com/en-us/articles/15401661-best-efforts-running)
  - [Best Efforts (Cycling)](https://support.strava.com/en-us/articles/15401645-best-efforts-cycling)
  - [Troubleshooting Best Efforts](https://support.strava.com/en-us/articles/15402001-troubleshooting-best-efforts)
  - [Estimated Best Efforts for Running (archive 2022)](https://web.archive.org/web/20221202062530/https://support.strava.com/hc/en-us/articles/216917127-Estimated-Best-Efforts-for-Running)
  - [API reference](https://developers.strava.com/docs/reference/)
- Garmin, sources secondaires :
  - [Manuel Forerunner 265](https://www8.garmin.com/manuals/webhelp/GUID-F41EAFB3-6CC9-42DE-9C6C-9E358DBB0671/EN-US/GUID-51F2755C-0909-4C39-9540-B9F4F1D3E156.html)
  - [Forum : PR don't match distance](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-iOS/389629/personal-records-don-t-match-distance)
  - [Forum : how does Garmin calculate record time](https://forums.garmin.com/sports-fitness/running-multisport/f/forerunner-965/346987/how-does-garmin-calculates-record-time)
  - [Forum : personal records calculation](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-andriod/217810/personal-records-calculation)
- Runalyze :
  - [`SubSegmentMaximization.php`](https://github.com/Runalyze/Runalyze/blob/5669237a78c7d3512df969052fd0d97e5dca6820/inc/core/Calculation/Math/SubSegmentMaximization.php)
  - [Aide : race result suggestions](https://runalyze.com/help/article/race-result-suggestions)
- Golden Cheetah : [`PeakPace.cpp`](https://github.com/GoldenCheetah/GoldenCheetah/blob/c6468970862d17060160d1d6b37904f20c4acee4/src/Metrics/PeakPace.cpp#L730-L771), plus `src/Gui/AddIntervalDialog.cpp` et `src/FileIO/RideFileCache.cpp` au même commit.
- intervals.icu :
  - [Forum : best pace achievements](https://forum.intervals.icu/t/best-pace-achievements-for-running-et-al/13029)
  - [Forum : pace curves and best efforts](https://forum.intervals.icu/t/pace-curves-and-best-efforts-for-running-etc/12929)
  - [Forum : swim records based on elapsed time](https://forum.intervals.icu/t/swim-records-based-on-elapsed-time-separate-pace-zones-by-pool-length/124761)
  - [API docs](https://intervals.icu/api/v1/docs)
- Code Nervo :
  - `packages/core/src/activities/domain/compute-analysis.ts`, `compute-metrics.ts`, `clean-trace.ts`, `pauses.ts`
  - `packages/core/src/activities/services/official-values.ts`
  - `packages/core/src/activities/use-cases/reprocess-activity.use-case.ts`, `reconcile-stuck-activities.use-case.ts`
  - `packages/contracts/src/activities/trace.ts`
  - ADR-021 §1, ADR-031 §4 et §12, ADR-033 §5, ADR-036 §6-7.
