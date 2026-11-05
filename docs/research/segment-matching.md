# Recherche : appariement des Segments et coût du rétro-appariement

- **Ticket** : [#225 Algorithme d'appariement des Segments et coût du rétro-appariement](https://github.com/echimine/clone-strava/issues/225) (carte wayfinder [#223 Segments et Records dans l'app](https://github.com/echimine/clone-strava/issues/223))
- **Date** : 2026-11-05
- **Question** : comment apparier un Segment à une Activité de façon fiable et rapide, comment calculer le temps de l'Effort, quelle trace utiliser (trace stockée ou route publique après zone de confidentialité), et à quel coût rejouer l'appariement sur l'historique quand un Segment est créé ?
- **Sources** : centre d'aide Strava, référence de l'API Strava v3, brevet Strava US 9 116 922 (« Defining and matching segments »), Eiter & Mannila 1994 (Fréchet discret), Newson & Krumm 2009 (map-matching HMM), documentation PostGIS et PostgreSQL, documentation BullMQ, et le code du dépôt à `main` (5d6c6b4). Tout a été lu le **2026-11-05**. Les citations sont verbatim. Le micro-benchmark du §7 a été fait le même jour (Node 24.14.0, Apple M5 Pro).

> Vocabulaire : « Segment », « Effort », « Activité », « Pause », « Enregistrement » sont les termes du glossaire (`CONTEXT.md`). « Trace » désigne les points horodatés de `trace.json.gz` ; « route » désigne `activity_track.route`, la LineString publique.

---

## TL;DR

1. **Strava ne publie pas son algorithme**, mais ses pages d'aide et son brevet en donnent la forme : le temps démarre et s'arrête sur les points de la trace **les plus proches** du départ et de l'arrivée du Segment, **sans interpolation** ; l'appariement est volontairement **« un peu lâche »** pour absorber la dérive GPS ; un trou dans les données déclenche un **« Gap Threshold »** ; le classement se fait au **temps écoulé** (« Segments and Best Efforts are always based on elapsed time ») ; une Activité peut avoir **plusieurs Efforts** sur le même Segment (l'API expose `start_index` / `end_index` par Effort). Le brevet donne des ordres de grandeur : rayon de tolérance de **50 m**, ligne de départ virtuelle de **100 m**, seuils de recouvrement de **65 %** (lâche) et **80 %** (serré).
2. **Algorithme recommandé pour `matchSegment`** (pur, TypeScript) : (a) détecter les **franchissements orientés** d'une ligne de départ et d'une ligne d'arrivée virtuelles, perpendiculaires au Segment ; (b) pour chaque départ, chercher la première arrivée qui suit et vérifier le **suivi du tracé** sur la portion entre les deux, ré-échantillonnée tous les 10 m : **couverture** (≥ 90 % des points du Segment à moins de 25 m) et **ordre** (**Fréchet discret** ≤ 50 m, qui interdit le sens inverse et les allers-retours) ; (c) rejeter s'il y a un **trou** (deux points consécutifs trop éloignés, ou une Pause pendant laquelle l'athlète s'est déplacé) ; (d) **interpoler** l'instant de chaque franchissement entre les deux points qui l'encadrent. Seuils de départ, à calibrer sur des fixtures réelles.
3. **Temps de l'Effort = temps écoulé**, Pauses comprises, entre les deux franchissements interpolés, comme Strava. Interpoler est un écart volontaire avec Strava : c'est quasi gratuit et ça rend le temps indépendant de l'échantillonnage (important pour les imports peu denses).
4. **Apparier sur la trace stockée nettoyée** (avant zone de confidentialité), comme l'Activity analysis (ADR-036 §6), et non sur `activity_track.route` : la route n'a **pas d'horodatage**, est simplifiée (Douglas-Peucker 5 m) et amputée des 200 m par défaut autour du départ et de l'arrivée. Un Effort dont le départ ou l'arrivée tombe dans la zone de confidentialité est **conservé mais privé** (hors classement), exactement la règle de Strava.
5. **PostGIS ne sert qu'au préfiltre indexé.** Les colonnes sont en `geometry(…, 4326)` : `ST_DWithin`, `ST_FrechetDistance` et `ST_HausdorffDistance` y travaillent **en degrés**, pas en mètres ; caster en `geography` donne des mètres mais ne passe plus par les index GiST existants (posés sur la colonne `geometry`). Et `ST_FrechetDistance` compare deux lignes entières, alors qu'un Effort n'est qu'une sous-partie de l'Activité. Donc : SQL = candidats par `&&` / `ST_DWithin` avec une marge en degrés surestimée ; TypeScript = test exact en mètres et chronométrage.
6. **Rétro-appariement** : les Activités candidates se trouvent par l'index `activity_track_route_gist_idx` (même sport, `processed`, route passant près du départ **et** de l'arrivée, marge élargie de 2 × le rayon de la zone de confidentialité). Le coût par candidate est dominé par la lecture de `trace.json.gz` dans le bucket (≈ 0,5 Mo de JSON pour 1 h à 1 Hz, de l'ordre de 100 Ko compressés, estimation à mesurer) ; le calcul géométrique est négligeable (Fréchet discret mesuré à **2 ms pour 5 km**, 64 ms pour 50 km). Découpage recommandé : un job **par page de ~200 candidates**, chaîné par curseur, avec un id déterministe, et un seul recalcul de classement à la fin.

---

## 1. Ce que Strava dit de son appariement

### 1.1 Centre d'aide

[Segment Matching Issues](https://support.strava.com/hc/en-us/articles/216918187-Segment-Matching-Issues) :

- Bornes : *« When we match you to a segment, we choose the GPS points from your file that fall closest to the segment's start and end. »* Conséquence assumée : *« you can be timed over portions of your activity that are slightly longer or shorter than the actual segment length. »*
- Tolérance : l'algorithme *« can be a little loose in its matching »* pour absorber la dérive, ce qui peut produire de faux appariements.
- Cause n° 1 d'échec : *« The most common reason a segment doesn't match on a ride or run is GPS drift during your activity recording. »* La dérive *« can cause you to trigger our "Gap Threshold" in the middle of a segment. »*
- Échantillonnage : *« if you have the option to set your recording interval, we recommend 1-second intervals. »*
- Confidentialité : quand un Segment *« starts or ends within a portion of your activity that is hidden »*, l'appariement a lieu mais est privé ; ces Efforts *« are not eligible to appear on public segment leaderboards or receive public achievements. »*

[How Do I Create Good Segments on Strava?](https://support.strava.com/en-us/articles/15401997-how-do-i-create-good-segments-on-strava) :

- *« we don't interpolate or extrapolate GPS data to normalize the exact start and end positions »*.
- *« Very short segments, for example sprints that take less than 30 seconds to complete »* sont plus sujets aux erreurs ; *« any deviation from the segment's route will prevent it from matching your activity. »*
- Tunnels : *« the best solution is to simply avoid creating segments that include tunnels longer than 500 meters. »*
- Bornes près d'un carrefour : *« placing the endpoint of your segment too close to an intersection can lead to stopped time being included »*. Lacets : *« extend the segment as far from its own "tail" as possible »*.
- Tracés parallèles ou qui se chevauchent : *« it may not be possible for Strava to provide mutually exclusive results »*.

[Resting Time in Segment Efforts](https://support.strava.com/hc/en-us/articles/115000248810-Resting-Time-in-Segment-Efforts) :

- *« All our segments are ranked according to "Total Elapsed Time." »*, parce que *« in a race, the clock keeps running even if you stop. »*
- *« To account for moderate GPS drift, our segment matching algorithm has to be a little loose. »* ; *« Resting time can be captured in a segment effort if you rest or turn around near the beginning or end of the segment. »* ; *« Moving past the segment start point can trigger the timer. »* La page conseille de s'arrêter à environ **70 m** des bornes, ce qui donne une idée de la largeur de leur zone de déclenchement.

[Moving Time, Speed, and Pace Calculations](https://support.strava.com/en-us/articles/15401804-moving-time-speed-and-pace-calculations) : *« Segments and Best Efforts are always based on elapsed time. »*

[Edit Map Visibility](https://support.strava.com/en-us/articles/15402012-edit-map-visibility) : par défaut *« the first and last 200 meters of your future activity maps will be hidden »* ; *« You will be matched to any segments within the hidden portion of the activity. However, your segment times will not appear on those segments' leaderboards and will not count toward segment challenges. »*

### 1.2 API Strava v3

Dans la [référence de l'API](https://developers.strava.com/docs/reference/), le modèle `DetailedSegmentEffort` porte à la fois `elapsed_time` (*« The effort's elapsed time »*) et `moving_time` (*« The effort's moving time »*), et surtout `start_index` (*« The start index of this effort in its activity's stream »*) et `end_index`. Un Effort est donc rattaché à des **indices de points** de la trace (cohérent avec « pas d'interpolation »), et une Activité renvoie un tableau `segment_efforts`, ce qui permet plusieurs Efforts sur le même Segment.

### 1.3 Brevet « Defining and matching segments »

[US 9 116 922 B2](https://patents.google.com/patent/US9116922) (Strava). Le brevet décrit une famille de mises en œuvre, pas forcément celle en production ; les nombres sont des exemples (« e.g. ») :

- Deux niveaux : une Activité est un *loose match* si *« their percentage of match exceeds a first threshold »* (*« e.g., 65% or greater »*), un *tight match* au-delà d'un second (*« e.g., 80% »*), à condition que *« the effort crosses the start and finish lines associated with the stored segment »*.
- Tolérance : *« a tolerance zone that is indicated by a radius of a selected length (e.g., 50 meters) »*.
- Préfiltre spatial par tuiles : *« each tile can be 20 meters by 20 meters »*, puis rectangles englobants (MBR) ; le pourcentage de match est *« the ratio between the number of overlapped MBRs of the segment to the total number of MBRs for the segment »*.
- Lignes virtuelles : *« The length of virtual start line can be selected to any appropriate length (e.g., 100 meters) »* ; le franchissement est détecté *« if two consecutive points are found to be on different sides of the line »*.
- Passages multiples : *« if the selected point has been crossed more than once in the effort »*, avec l'exemple *« the selected start point was crossed at three different times »*.
- Sens : les revendications parlent de *« determining an orientation of the path »*, et l'ordre temporel des points est explicite (*« Point P1(t0) was passed earlier in time than P2(t1) »*).

**Ce que je n'ai pas trouvé** : aucun billet d'ingénierie Strava ne décrit l'algorithme en production, ni la valeur du « Gap Threshold », ni la règle exacte du classement (un Effort par athlète ou tous ses Efforts). Ce dernier point relève du ticket sur les classements.

## 2. Littérature : comparer deux tracés

### 2.1 Fréchet discret

[Eiter & Mannila, *Computing Discrete Fréchet Distance*, CD-TR 94/64, 1994](https://haendel.kr.tuwien.ac.at/staff/eiter/et-archive/files/cdtr9464.pdf) :

- Intuition : *« A man is walking a dog on a leash: the man can move on one curve, the dog on the other; both may vary their speed, but backtracking is not allowed. »*
- Pourquoi pas Hausdorff : *« The Fréchet distance is a measure of similarity between curves that takes into account the location and ordering of the points along the curves. Therefore it is often better than the well-known Hausdorff distance. »*
- Version discrète (*coupling distance*) : *« δdF is an upper bound for δF, and […] the difference between these measures is bounded by the length of the longest edge of the polygonal curves »*, calculable *« in O(pq) time using a very simple algorithm »*. D'où la recette : *« First compute proper polygonal approximations to the curves and then compute their coupling distance »*. Autrement dit : **ré-échantillonner finement** (pas de 10 m → écart au Fréchet continu ≤ 10 m), puis Fréchet discret.

Pour un Segment, l'ordre compte : Hausdorff ne voit pas la différence entre un Segment parcouru dans le bon sens, à l'envers, ou par un aller-retour qui touche tous ses points. Fréchet, si.

### 2.2 Hausdorff (PostGIS)

[`ST_HausdorffDistance`](https://postgis.net/docs/ST_HausdorffDistance.html) : *« This algorithm is NOT equivalent to the standard Hausdorff distance »*, *« it computes an approximation that is correct for a large subset of useful cases »*, *« a useful metric for line matching »* pour des lignes à peu près parallèles et de longueur proche. Utile comme mesure de **couverture**, insuffisant seul pour l'ordre.

### 2.3 Map-matching (HMM)

[Newson & Krumm, *Hidden Markov Map Matching Through Noise and Sparseness*, ACM GIS 2009](https://microsoft.com/en-us/research/wp-content/uploads/2016/12/map-matching-ACM-GIS-camera-ready.pdf) : apparier un tracé à un **graphe routier** (Viterbi sur les tronçons candidats). Trois faits utiles ici, même si on n'a pas de graphe :

- Bruit d'un GPS grand public : *« For our test data, this value was σz = 4.07 meters »*.
- Les approches purement géométriques sont *« sensitive to measurement noise and sampling rate »* ; leur algorithme reste bon jusqu'à 30 s entre points (*« the error is only 0.11% even when the sampling period grows to 30 seconds »*).
- Ils ignorent les candidats à plus de 200 m d'un point, et découpent le trajet quand une rupture dure plus de 180 s.

Le map-matching (Mapbox Map Matching, OSRM, Valhalla) suppose un réseau routier ; un Segment Nervo est une simple polyligne, souvent sur sentier. **Hors sujet pour `matchSegment`**, mais une piste si un jour les Segments étaient accrochés au réseau.

## 3. Ce qui existe dans le code

- `packages/core/src/segments/domain/match-segment.ts` : `matchSegment(route: TracePoint[], candidate: { segmentId, path: TracePoint[] }, toleranceM): SegmentMatch | null`, stub. Renvoie **un** match au plus et `elapsedTimeS` seulement.
- `SegmentRepository.findCandidatesNearRoute(sportTypeCode, routeWkt)` et `SegmentEffortRepository.upsert` / `recomputeLeaderboard` : stubs. Le commentaire d'`upsert` dit *« one effort per activity/segment »*.
- Schéma `segments.segment` : `path geometry(LineString,4326)`, `start_point`, `end_point`, index GiST `segment_path_gist_idx` et `segment_start_point_gist_idx` (**pas d'index sur `end_point`**). `segment_effort` : `elapsed_time_s`, `started_at`, `rank`, pas d'indice de point.
- `activities.activity_track.route` : *« Simplified route shown to others; the privacy zone is applied before storage »*, index `activity_track_route_gist_idx`. Construite dans `OfficialValuesService.compute` : `cleanTrace` → `applyPrivacyZone` → `simplifyTrack(zoned, ROUTE_TOLERANCE_M = 5)`.
- Trace v2 (`packages/contracts/src/activities/trace.ts`) : points `{ timestampMs, lat, lon, elevationM?, horizontalAccuracyM?, speedMs?, heartRateBpm?, cadenceRpm? }` et `pauses: [{ startMs, endMs }]`, aucun point écrit pendant une Pause (ADR-031). Limite 50 Mo.
- `cleanTrace` retire les points de précision > 50 m (`MAX_TRACE_ACCURACY_M`) et les vitesses impossibles (`run` 12 m/s, `walk`/`hike` 5 m/s, `ride` 35 m/s).
- Zone de confidentialité : `user_profile.privacy_zone_radius_m`, **200 m par défaut** (même valeur que Strava). `applyPrivacyZone` coupe les points à moins de ce rayon du premier et du dernier point.
- PostGIS : image `postgis/postgis:17-3.5`, donc `ST_FrechetDistance` (*« Availability: 2.4.0 - requires GEOS >= 3.7.0 »*) et `ST_LineSubstring` en `geography` (*« Enhanced: 3.4.0 »*) sont disponibles.
- ADR-021 §2 : `segments` (couche 3) ne peut appeler que `activities` et `sports`, via leur service. Il ne lit **ni** `activity_track` **ni** `user_profile` directement (§6 : *« Repositories only touch the module's own tables »*) et ne connaît pas `users`.
- ADR-019 §8 : *« check that the route actually follows the segment from end to end (tolerance of a few tens of meters) »* ; *« compute the time from the raw trace »*.

## 4. Algorithme proposé pour `matchSegment`

Entrées : la trace **nettoyée** de l'Activité (points horodatés + Pauses), le tracé du Segment, des paramètres passés en argument (comme `@repo/geo`). Sortie : **une liste** d'Efforts (pas `| null`), chacun avec ses indices de points, son instant de départ et son temps écoulé.

### 4.1 Préparation du Segment (une fois, à la création)

- Ré-échantillonner `path` tous les **10 m** (`resampleAlongTrack` de `@repo/geo`).
- Calculer une **ligne de départ** : segment perpendiculaire au cap des ~20 premiers mètres, centré sur le départ, demi-largeur **W = 25 m** ; idem pour l'**arrivée**. Le brevet prend 100 m de long (50 m de part et d'autre) ; on part plus serré et on calibre.

### 4.2 Franchissements orientés

- Projeter la trace dans un repère local métrique (équirectangulaire centré sur le Segment : à l'échelle de quelques kilomètres l'erreur est négligeable).
- Un **départ** = deux points consécutifs `p[k]`, `p[k+1]` de part et d'autre de la ligne de départ, **dans le sens du Segment** (signe du produit vectoriel avec le cap), le segment `[p[k], p[k+1]]` coupant la ligne à moins de W du point de départ. Idem pour les **arrivées**. C'est le test du brevet (*« two consecutive points […] on different sides of the line »*), robuste à un échantillonnage clairsemé, contrairement à « un point à moins de x m ».
- Une paire qui **enjambe une Pause** (`straddlesPause`, déjà dans `activities/domain/pauses.ts`) ne compte pas comme franchissement : on ne sait pas où l'athlète était.

### 4.3 Suivi du tracé entre un départ et une arrivée

Pour chaque départ, dans l'ordre, prendre la **première** arrivée qui suit, puis tester la portion `p[k+1 … m]` :

1. **Trou** : rejeter si deux points consécutifs sont à plus de **G** mètres (point de départ : 100 m ; à 1 Hz, un coureur fait 3–5 m, un cycliste ~10 m ; un import échantillonné à 5 s donne ~50 m à vélo), ou si l'athlète s'est déplacé de plus de τ pendant une Pause (déplacement pendant une Pause manuelle = trajet en voiture possible). C'est notre « Gap Threshold ».
2. **Couverture** : ré-échantillonner la portion tous les 10 m ; au moins **90 %** des points du Segment doivent être à moins de **τ = 25 m** de la portion (le *tight match* du brevet est à 80 % ; on est plus strict parce que le Fréchet ci-dessous rattrape déjà les petits écarts).
3. **Ordre et sens** : **Fréchet discret ≤ τF = 50 m** entre la portion et le Segment ré-échantillonnés. Interdit le sens inverse, les raccourcis et les allers-retours que la couverture laisse passer. Version « décision » (« ≤ τF ? ») en programmation dynamique sur deux lignes glissantes : temps O(p·q), mémoire O(q).
4. Si le test échoue, essayer l'arrivée suivante, puis le départ suivant (un faux départ suivi d'un vrai passage doit encore matcher). Une fois un Effort accepté, reprendre la recherche **après son arrivée** : deux Efforts d'une même Activité ne se chevauchent pas, mais une boucle parcourue trois fois donne trois Efforts.

Valeurs à calibrer sur des fixtures réelles (traces Nervo et imports GPX/FIT), à garder en paramètres. Ordres de grandeur qui les encadrent : bruit GPS σ ≈ 4 m (Newson & Krumm), points de précision > 50 m déjà retirés par `cleanTrace`, tolérance de 50 m dans le brevet, « quelques dizaines de mètres » dans ADR-019 §8.

### 4.4 Temps de l'Effort

- Instant de départ = **interpolation linéaire** entre `t[k]` et `t[k+1]` au point où `[p[k], p[k+1]]` coupe la ligne de départ ; idem pour l'arrivée.
- **Temps écoulé = t_arrivée − t_départ**, Pauses comprises, comme Strava (*« always based on elapsed time »*) et comme le temps total d'ADR-019 §5 (amendé par ADR-031). C'est aussi la seule mesure qui ne se triche pas avec le bouton Pause.
- Le temps en mouvement de l'Effort (même règle que `computeMetrics` : on saute les paires qui enjambent une Pause) peut être calculé et affiché, comme le fait l'API Strava, mais **le classement se fait au temps écoulé**.
- Strava n'interpole pas et prend les points les plus proches ; Nervo peut faire mieux pour presque rien : à 1 Hz l'écart est < 1 s, mais pour un import à 5–10 s entre points il atteint plusieurs secondes, et il dépend du hasard de l'échantillonnage.
- Garder `startIndex` / `endIndex` (comme l'API Strava) : utile pour afficher l'Effort sur la carte et les courbes, et pour la clé d'unicité des passages multiples.

### 4.5 Boucles et cas limites

- **Segment en boucle** (départ ≈ arrivée) : la ligne d'arrivée est franchie dès le départ. La règle « première arrivée qui suit + couverture + Fréchet » échoue alors sur la portion vide et passe à l'arrivée suivante, ce qui marche. Plus simple et plus sûr : **refuser à la création** un Segment dont le départ et l'arrivée sont à moins de ~2 × W l'un de l'autre (règle à trancher dans le ticket « création de Segment »).
- **Lacets, tracés parallèles, Segments courts** : les recommandations de Strava (éviter < 30 s, bornes loin des carrefours et de leur propre « queue », tunnels < 500 m) sont des règles de création, à reprendre comme validations ou conseils dans l'app.
- **Trace sans GPS** (natation) : pas de Segment (carte #223 : Segments seulement pour `run`, `ride`, `walk`, `hike`).

### 4.6 Ce qui reste en SQL, ce qui va dans `matchSegment`

| Étape | Où | Pourquoi |
|---|---|---|
| Trouver les Segments proches d'une Activité, ou les Activités proches d'un Segment | SQL, index GiST | seul endroit où l'index sert |
| Franchissements, couverture, Fréchet, trous, temps | `matchSegment` pur (TS) | besoin des horodatages (absents de la base) ; mètres et non degrés ; sous-portion de trace ; testable sans base (ADR-021 §6) |
| Rang dans le classement | SQL (`rank() over (…)`) | ticket classements |

Pourquoi ne pas faire le test exact en PostGIS :

- `ST_FrechetDistance` / `ST_HausdorffDistance` : *« Units are in the units of the spatial reference system of the geometries »*, donc **des degrés** en SRID 4326. Il faudrait `ST_Transform` vers une projection métrique choisie selon le lieu (le monde entier, carte #223).
- Elles comparent deux lignes entières. Isoler la sous-partie de la route avec [`ST_LineLocatePoint`](https://postgis.net/docs/ST_LineLocatePoint.html) (*« as a fraction of 2d line length »*) et [`ST_LineSubstring`](https://postgis.net/docs/ST_LineSubstring.html) est possible, mais casse sur les boucles (une seule fraction par point) et ne donne pas le temps.
- La route en base est simplifiée, amputée et sans temps : le chronométrage doit de toute façon lire `trace.json.gz`.

## 5. Trace stockée ou route publique ?

**Trace stockée nettoyée** (mêmes points que la distance officielle et l'Activity analysis), pour quatre raisons :

1. **Horodatage** : seule la trace en a ; ADR-019 §8 dit déjà *« compute the time from the raw trace »*.
2. **Précision** : la route est simplifiée par Douglas-Peucker à 5 m ; la tolérance de la couverture (25 m) l'absorberait, mais pas les bornes interpolées.
3. **Zone de confidentialité** : avec la route, un Segment qui part de la rue de l'athlète (dans les 200 m) ne serait **jamais** apparié, même pour lui. Strava apparie quand même et rend l'Effort privé.
4. **Cohérence** : `cleanTrace` est déjà appliqué avec la vitesse plausible du sport ; reprendre le même nettoyage évite deux vérités.

Règle de confidentialité proposée, calquée sur Strava : un Effort dont **le départ ou l'arrivée est à moins de `privacy_zone_radius_m`** du premier ou du dernier point de l'Activité est enregistré mais **privé** (visible par son auteur seul, hors classement et hors Local Legend). Sinon, un classement public révélerait qu'un athlète passe chaque jour au bout d'un Segment qui démarre devant chez lui. À trancher dans le ticket « cycle de vie et confidentialité » de la carte, avec la visibilité de l'Activité. Chez Strava, les classements filtrés n'affichent que *« segment times only from activities set to "Everyone." »*, et un athlète ne voit pas ses temps sur ces classements *« if your activities are set to "Followers" or "Only You." »* ([Privacy Controls FAQ](https://support.strava.com/en-us/articles/15401776-strava-s-privacy-controls-faq)).

Conséquence ADR-021 : `segments` ne lit ni le bucket ni `user_profile` directement pour ce besoin. Il faut une méthode du service `activities` qui renvoie, pour une Activité, la **trace nettoyée, ses Pauses, le rayon de zone, le sport, la visibilité et l'auteur** (`activities` dépend déjà de `users`), et une méthode « Activités proches d'un tracé » pour le rétro-appariement (§6).

## 6. Trouver les candidats par index

### 6.1 Ce que fait l'index

- *« Spatial indexes store only the bounding box of geometries »* ([manuel PostGIS, §4.9](https://postgis.net/docs/manual-3.5/using_postgis_dbmanagement.html)) ; l'évaluation est en deux passes, boîte puis test exact ([atelier PostGIS, indexation](https://postgis.net/workshops/postgis-intro/indexing.html)).
- [`ST_DWithin`](https://postgis.net/docs/ST_DWithin.html) : *« This function call includes a bounding box comparison that makes use of any indexes that are available on the geometries. »* En `geometry`, *« The distance is specified in units defined by the spatial reference system »*, donc en degrés ; en `geography`, *« units are in meters »*.
- [`&&`](https://postgis.net/docs/geometry_overlaps.html) : *« returns TRUE if the 2D bounding box of geometry A intersects the 2D bounding box of geometry B »* et *« will make use of any indexes that may be available »*.
- Un `route::geography` dans la requête est une **expression** ; PostgreSQL n'utilise un index que s'il porte sur cette expression ([Indexes on Expressions](https://www.postgresql.org/docs/current/indexes-expressional.html) : *« This query can use an index if one has been defined on the result of the `lower(col1)` function »*). Les index existants sont sur la colonne `geometry`.

D'où le motif : **filtre indexé en degrés avec une marge surestimée**, puis test exact en mètres en TS. Une marge de δ mètres vaut au plus δ / (111 320 × cos φmax) degrés, φmax étant la latitude la plus éloignée de l'équateur de la zone (bornée à ~80° pour éviter l'explosion). Ça élargit un peu la boîte en latitude, ce qui ne coûte que quelques candidats en trop.

### 6.2 Appariement à la fin du traitement (`match-segments`, par Activité)

Calculer la boîte englobante de la trace nettoyée dans le worker, puis (esquisse) :

```sql
SELECT id, ST_AsGeoJSON(path) AS path
FROM segments.segment
WHERE sport_type_code = $sport
  AND start_point && ST_Expand(ST_MakeEnvelope($minLon, $minLat, $maxLon, $maxLat, 4326), $deltaDeg)
  AND ST_DWithin(start_point, $traceLine, $deltaDeg)
  AND ST_DWithin(end_point,   $traceLine, $deltaDeg);
```

`$traceLine` est la trace nettoyée **non amputée** simplifiée, passée en paramètre : elle ne quitte pas le serveur et n'est jamais stockée. Le premier prédicat passe par `segment_start_point_gist_idx`. δ ≈ 50 m. Ceci remplace la signature actuelle `findCandidatesNearRoute(sportTypeCode, routeWkt)`, qui supposait la route publique.

### 6.3 Rétro-appariement (par Segment)

Requête côté module `activities` (ses tables), exposée par son service :

```sql
SELECT a.id, a.user_id
FROM activities.activity a
JOIN activities.activity_track t ON t.activity_id = a.id
WHERE a.sport_type_code = $sport
  AND a.processing_status = 'processed'
  AND t.route && ST_Expand($segmentPath, $deltaDeg)          -- index activity_track_route_gist_idx
  AND ST_DWithin(t.route, $segmentStart, $deltaDeg)
  AND ST_DWithin(t.route, $segmentEnd,   $deltaDeg)
  AND a.id > $cursor
ORDER BY a.id
LIMIT 200;
```

La route publique est amputée autour du départ et de l'arrivée de l'Activité. Si le départ du Segment est dans la zone (à moins de r du premier point), il est à environ **2r** au plus du premier point gardé de la route (inégalité triangulaire). La marge doit donc être **δ + 2 × r_max**, soit ~450 m avec le rayon par défaut de 200 m. C'est un préfiltre ; le test exact se fait sur la trace. Une Activité entièrement dans sa zone (`route` nulle) n'est pas trouvée : elle n'aurait produit qu'un Effort privé.

## 7. Coût

### 7.1 Par Activité candidate

| Poste | Ordre de grandeur | Source |
|---|---|---|
| Lecture de `trace.json.gz` (GET bucket) | une requête S3 par Activité ; c'est le poste dominant | ADR-021 (`storage`), `OfficialValuesService.loadTrace` |
| Taille de la trace | ≈ 0,56 Mo de JSON pour 1 h à 1 Hz (3 600 points avec altitude, précision, vitesse et FC) ; ≈ 64 Ko gzip sur données synthétiques ; de vraies coordonnées en double précision compressent sans doute moins bien | estimation, script synthétique du 2026-11-05 ; **à mesurer sur le bucket** |
| Décompression + Zod + `cleanTrace` | quelques ms pour 3 600 points | non mesuré |
| Fréchet discret (décision, deux lignes glissantes, 10 m de pas) | **0,7 ms** pour 2 km, **2,2 ms** pour 5 km, **10 ms** pour 20 km, **64 ms** pour 50 km | mesuré, Node 24.14.0, Apple M5 Pro |
| Couverture, franchissements | linéaires, négligeables | — |

Le calcul géométrique est donc négligeable ; le coût d'un rétro-appariement est **≈ N candidates × (GET + parse)**. L'app n'est pas publiée (mémoire du projet) : N reste petit aujourd'hui. Pour un Segment populaire avec 10 000 candidates et, **par hypothèse non mesurée**, ~50 ms par candidate, compter de l'ordre de 8 minutes de worker sur une seule file : acceptable en tâche de fond, à condition de ne pas bloquer `match-segments`. Le filtre « départ **et** arrivée près de la route » écarte l'essentiel des Activités qui ne font que croiser le Segment.

Pour la mémoire du Fréchet sur de longs Segments : la matrice complète 5 000 × 5 000 ferait 25 M cases ; la version décision n'a besoin que de deux lignes (O(q)).

### 7.2 Découpage en jobs

- Un job dédié, par exemple `match-segment-history` dans la file `segments`, payload `{ segmentId, cursor }`. Chaque job : lit une page de **~200** candidates (§6.3), apparie chacune, upsert les Efforts, puis **enfile la page suivante** avec un id déterministe `match-segment-history-{segmentId}-{lastActivityId}` (pas de `:` : *« Custom job ids must not contain the : separator »*, [BullMQ, Job Ids](https://docs.bullmq.io/guide/jobs/job-ids)). Un id déjà présent est ignoré (*« that job will just be ignored and not added to the queue at all »*), donc un rejeu ne duplique pas la chaîne.
- **Le classement est recalculé une fois**, par le dernier job (page incomplète), puis l'événement est émis. Pendant le rétro-appariement le Segment peut être affiché « en cours de calcul ».
- Upsert idempotent : si une nouvelle Activité est traitée pendant le rétro-appariement, son propre `match-segments` trouve aussi le Segment ; les deux écrivent le même Effort sans doublon.
- Ne pas affamer `match-segments` : concurrence basse pour ce job (1–2) ou une priorité BullMQ plus faible. Même retry et même rétention que les autres (`DEFAULT_JOB_RETRY`, ADR-038 §14).
- Alternative écartée : enfiler un `match-segments` par Activité candidate. C'est plus simple mais ça rejoue **tous** les Segments de chaque Activité et recalcule le classement N fois. `addBulk` réduit les allers-retours (*« Adding jobs in bulk can be faster because it reduces roundtrips to the backend »*, [BullMQ, Adding jobs in bulk](https://docs.bullmq.io/guide/queues/adding-bulks)) mais ne change rien au travail fait.
- Même mécanisme pour les autres rejeux prévus par ADR-033 §9 (changement de sport) et pour un futur changement d'algorithme (version d'appariement, comme `ACTIVITY_ANALYSIS_VERSION` et le backfill d'ADR-036 §7).

## 8. Ce que ça implique pour Nervo (recommandations)

1. Changer la signature de `matchSegment` : entrée = trace nettoyée + Pauses + Segment préparé + paramètres ; sortie = **liste** d'Efforts `{ startIndex, endIndex, startedAt, elapsedTimeS, movingTimeS? }`. Écrire l'algorithme du §4 en TDD sur des fixtures (aller simple, sens inverse, aller-retour, boucle ×3, trou GPS, Pause avec déplacement, départ dans la zone de confidentialité, import à 5 s).
2. Clé d'unicité de `segment_effort` : `(activity_id, segment_id, start_index)` au lieu d'un Effort par Activité et par Segment ; ajouter `start_index`, `end_index` et un drapeau « privé » (Effort dans la zone de confidentialité). À porter dans l'amendement d'ADR-017.
3. Classement au **temps écoulé**, bornes **interpolées** (écart assumé avec Strava).
4. Apparier sur la **trace stockée nettoyée** ; Effort dont le départ ou l'arrivée est dans la zone de confidentialité = **privé** (hors classement, hors Local Legend).
5. PostGIS = préfiltre indexé en degrés avec marge ; tout le test exact en TypeScript. Ajouter éventuellement un index GiST sur `segment.end_point` (aujourd'hui absent).
6. Exposer dans `ActivitiesService` : « trace d'appariement d'une Activité » et « Activités d'un sport proches d'un tracé, paginées par curseur ». `segments` n'accède à rien d'autre (ADR-021).
7. Rétro-appariement par **pages de ~200 candidates chaînées**, id déterministe, classement recalculé une fois à la fin, priorité plus basse que `match-segments`.
8. Règles de création à trancher ailleurs, inspirées de Strava : longueur minimale (~30 s d'effort), départ et arrivée éloignés l'un de l'autre, pas de tunnel > 500 m.

## Annexe : sources

- Strava, [Segment Matching Issues](https://support.strava.com/hc/en-us/articles/216918187-Segment-Matching-Issues)
- Strava, [How Do I Create Good Segments on Strava?](https://support.strava.com/en-us/articles/15401997-how-do-i-create-good-segments-on-strava)
- Strava, [Resting Time in Segment Efforts](https://support.strava.com/hc/en-us/articles/115000248810-Resting-Time-in-Segment-Efforts)
- Strava, [Moving Time, Speed, and Pace Calculations](https://support.strava.com/en-us/articles/15401804-moving-time-speed-and-pace-calculations)
- Strava, [Edit Map Visibility](https://support.strava.com/en-us/articles/15402012-edit-map-visibility)
- Strava, [Privacy Controls FAQ](https://support.strava.com/en-us/articles/15401776-strava-s-privacy-controls-faq)
- Strava, [API v3 reference](https://developers.strava.com/docs/reference/) (`DetailedSegmentEffort`)
- Strava, brevet [US 9 116 922 B2, Defining and matching segments](https://patents.google.com/patent/US9116922)
- T. Eiter, H. Mannila, [Computing Discrete Fréchet Distance](https://haendel.kr.tuwien.ac.at/staff/eiter/et-archive/files/cdtr9464.pdf), CD-TR 94/64, TU Wien, 1994
- P. Newson, J. Krumm, [Hidden Markov Map Matching Through Noise and Sparseness](https://microsoft.com/en-us/research/wp-content/uploads/2016/12/map-matching-ACM-GIS-camera-ready.pdf), ACM SIGSPATIAL GIS 2009
- PostGIS : [`ST_DWithin`](https://postgis.net/docs/ST_DWithin.html), [`ST_FrechetDistance`](https://postgis.net/docs/ST_FrechetDistance.html), [`ST_HausdorffDistance`](https://postgis.net/docs/ST_HausdorffDistance.html), [`ST_LineLocatePoint`](https://postgis.net/docs/ST_LineLocatePoint.html), [`ST_LineSubstring`](https://postgis.net/docs/ST_LineSubstring.html), [`&&`](https://postgis.net/docs/geometry_overlaps.html), [`ST_Expand`](https://postgis.net/docs/ST_Expand.html), [manuel 3.5, gestion des données](https://postgis.net/docs/manual-3.5/using_postgis_dbmanagement.html), [atelier, indexation](https://postgis.net/workshops/postgis-intro/indexing.html)
- PostgreSQL, [Indexes on Expressions](https://www.postgresql.org/docs/current/indexes-expressional.html)
- BullMQ, [Job Ids](https://docs.bullmq.io/guide/jobs/job-ids), [Adding jobs in bulk](https://docs.bullmq.io/guide/queues/adding-bulks)
