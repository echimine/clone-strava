# Recherche : source des altitudes d'un Itinéraire

- **Ticket** : [#14 Source des altitudes d'un Itinéraire](https://github.com/echimine/clone-strava/issues/14) (carte wayfinder [#5](https://github.com/echimine/clone-strava/issues/5))
- **Date** : 2026-10-10
- **Contexte** : décisions de [#9](https://github.com/echimine/clone-strava/issues/9) (l'app appelle Mapbox Directions directement ; **le serveur est la source de vérité** pour la distance et le D+ enregistrés, recalculés avec `compute-metrics`), de [#12](https://github.com/echimine/clone-strava/issues/12) (déviation assumée : on stocke le tracé, la distance et le D+) et de la recherche [#6](https://github.com/echimine/clone-strava/blob/research/mapbox-itinerary-routing/docs/research/mapbox-itinerary-routing.md).
- **Question** : d'où viennent les altitudes par point du tracé, à partir desquelles l'API calcule le D+ enregistré ? D'où vient l'estimation de D+ affichée pendant l'édition ?
- **Sources** : documentation officielle Mapbox, code source `mapbox-maps-ios` à la révision résolue par le projet, documentation Géoplateforme (cartes.gouv.fr, data.gouv.fr, `data.geopf.fr`), documentation et conditions Open-Meteo, page Copernicus Data Space et registre AWS Open Data, fichier de configuration GraphHopper et doc Valhalla. Tout a été lu le **2026-10-10**. Les citations sont verbatim. Les mesures de latence et de D+ (§6) ont été faites le même jour depuis un poste en France, avec le script décrit en annexe.

> Vocabulaire : « Itinéraire » et « Waypoint » sont les termes du domaine. « Tracé » désigne la géométrie renvoyée par Directions.

---

## TL;DR

1. **`MapboxMap.elevation(at:)` ne peut pas être la source enregistrée.** Le code de MapboxMaps 11.31.1 dit : *« Elevation is only available for the visible region on the screen »*. Le `TileStore` hors ligne accepte les tuiles DEM, mais il ne fait que pré-télécharger : il ne rend pas l'altitude interrogeable hors de l'écran. Pour couvrir tout l'Itinéraire, il faut le faire tenir à l'écran, donc dézoomer, donc lire un DEM plus grossier. Mapbox ne documente ni la précision ni la source de Terrain-DEM. Enfin, ça ne tourne que sur l'appareil, alors que #9 fait du serveur la source de vérité.
2. **API altimétrie IGN Géoplateforme** (RGE ALTI, MNT au pas de 1 m) : France entière, DOM inclus. Accès ouvert, **sans clé**, licence Etalab 2.0 (stockage autorisé avec mention de la source). Jusqu'à **5 000 points par requête**, **5 requêtes/s par IP**. Hors couverture, la réponse vaut `-99999`. Latence mesurée : 0,6–0,8 s pour 100 à 1 000 points, 2,8 s pour 5 000 points.
3. **Open-Meteo Elevation** (Copernicus GLO-90, 90 m) : couverture mondiale, 100 points par requête, latence d'environ 0,15 s. Gratuit **pour un usage non commercial** (600/min, 10 000/jour), données sous CC BY 4.0. Mais **Copernicus est un MNS** : il inclut *« buildings, infrastructure and vegetation »*. Mesuré à 100 points : D+ ×3,3 en ville (Paris, 97 m contre 29 m pour l'IGN) et ×2,4 en forêt (Fontainebleau, 106 m contre 44 m).
4. **DEM hébergé chez nous** (Copernicus GLO-30 en COG sur AWS, ou RGE ALTI téléchargé) : aucun quota ni dépendance réseau, mais il faut stocker et lire des rasters et maintenir un service. Avec Copernicus, on garde le biais MNS. Ce coût n'est pas justifié tant que l'IGN suffit.
5. **Densité d'échantillonnage** : ne pas utiliser les sommets bruts du tracé Directions, dont l'espacement est irrégulier. **Ré-échantillonner tous les 20 m environ** et appliquer un **seuil d'hystérésis de 2 m** sur les variations d'altitude. Mesuré : avec le seuil, le D+ reste stable entre 0,6 m et 50 m de pas (1 363 à 1 367 m sur une pente alpine, 20–22 m dans Paris, 37 m à Fontainebleau). Sans seuil, il gonfle avec la densité (29 → 51 m dans Paris).
6. **`compute-metrics` ne peut pas être réutilisé tel quel.** (a) Il saute tout segment dont la durée est `<= 0` *avant* de cumuler distance et D+. Un tracé sans horodatage donnerait donc 0 m et 0 m de D+. (b) Il ne lisse pas l'altitude du tout, alors qu'ADR-019 §5 parle de *« smoothed altitude »*. Il faut extraire une fonction pure distance + D+ (avec le seuil) partagée par les Activities et les Itinéraires.
7. **Recommandation** : **IGN côté serveur** pour le D+ enregistré. L'app envoie un tracé 2D, l'API ré-échantillonne, ajoute les altitudes IGN et calcule. Pour l'estimation pendant l'édition, **le même calcul via un endpoint de l'API** déclenché à la fin du glissement, pour que l'estimation et le chiffre enregistré soient identiques. Repli **Open-Meteo** pour les points hors France (`-99999`). Le détail et les alternatives sont au §8.

---

## 1. Sur l'appareil : `MapboxMap.elevation(at:)` et Terrain-DEM v1

### API (MapboxMaps 11.31.1)

Le projet résout `mapbox-maps-ios` 11.31.1, révision `6be7a1608d70c6d64eb9c57acb45f982f3953d09` (`apps/mobile/StravaClone.xcodeproj/.../Package.resolved`). Dans [`Sources/MapboxMaps/Foundation/MapboxMap.swift`](https://github.com/mapbox/mapbox-maps-ios/blob/6be7a1608d70c6d64eb9c57acb45f982f3953d09/Sources/MapboxMaps/Foundation/MapboxMap.swift), lignes 397–406 :

```swift
/// Gets elevation for the given coordinate.
///
/// - Note: Elevation is only available for the visible region on the screen.
///
/// - Parameter coordinate: Coordinate for which to return the elevation.
/// - Returns: Elevation (in meters) multiplied by current terrain
///     exaggeration, or empty if elevation for the coordinate is not available.
public func elevation(at coordinate: CLLocationCoordinate2D) -> Double? {
    return __map.getElevationFor(coordinate)?.doubleValue
}
```

Il n'existe pas d'autre API publique d'altitude dans ce fichier, rien d'équivalent à une requête hors écran.

### Données ([Terrain-DEM v1](https://docs.mapbox.com/data/tilesets/reference/mapbox-terrain-dem-v1/))

- *« Mapbox Terrain-DEM-v1 is only available for use in the Mapbox SDKs […] It is not available via the Raster Tiles API »*. Le serveur ne peut donc pas l'utiliser.
- *« Data is available up to zoom 14. Renderers will interpolate and smooth at higher zoom levels but will not increase the resolution of the data loaded by your application. »*
- *« Elevation data is mapped to 0.1 meter height increments »*.
- *« Mapbox Terrain-DEM uses multiple data sources depending on the zoom level and location. »* *« Different sources often use different vertical datum references »*. La page ne donne **aucune précision verticale** et ne nomme pas les sources.

### Peut-on charger le terrain le long de tout le tracé (`TileStore`) ?

- Les régions hors ligne acceptent les sources dont l'URL suit *« the Mapbox Raster DEM tile v1 URL schema »* ([Offline, concepts](https://docs.mapbox.com/ios/maps/guides/offline/concepts/)). Une région se définit par une géométrie (`TileRegionLoadOptions(geometry:descriptors:...)`), et la doc recommande *« more precise geometries (points/lines) instead of large polygons »* ([Manage offline data](https://docs.mapbox.com/ios/maps/guides/offline/manage-offline-data/)). On peut donc pré-télécharger les tuiles DEM le long d'une LineString.
- Limites : *« The cumulative number of unique tile packs used in the tile regions cannot be greater than 750. »* *« There are no guarantees about how long these resources will be cached. »*
- **Ce que la doc ne dit pas** : rien n'indique que `elevation(at:)` lit le `TileStore` pour une coordonnée hors écran. Le commentaire du code dit le contraire (« visible region »). Le `TileStore` accélère le chargement quand la caméra passe sur la zone, il ne lève pas la contrainte d'écran. Je n'ai pas testé sur appareil.
- Contournement possible : cadrer la caméra sur tout l'Itinéraire avant d'échantillonner. Mais la résolution suit alors le zoom. Pour une tuile DEM de 512 px, l'espacement des pixels vaut 40 075 016 m × cos(lat) / (512 × 2^z). À 45° N, cela donne environ **3,4 m à z14, 13,5 m à z12 et 54 m à z10**. Ce sont des valeurs calculées, pas documentées. Un Itinéraire de 50 km affiché sur un iPhone tient vers z11–z12.
- Facturation : *« Maps SDK MAUs cover any use of the Vector Tiles API and Raster Tiles API »* ([pricing iOS](https://docs.mapbox.com/ios/maps/guides/pricing/)). La page ne nomme pas les tuiles DEM ni les téléchargements hors ligne, donc la couverture est probable mais **non confirmée** (même constat que #6).

### Conditions

L'altitude est dérivée de contenu Mapbox (Product Terms §1.6 et §1.9(v), voir #6 §2). #12 a accepté une déviation pour le tracé, et elle pourrait s'étendre à l'altitude, mais ce n'est pas le point bloquant.

### Verdict

Valeur **instantanée et gratuite pour un affichage local**, par exemple pour lire l'altitude sous le doigt. Elle ne convient pas comme source enregistrée pour trois raisons : elle est limitée à l'écran, sa précision dépend du zoom et n'est pas documentée, et elle n'existe que sur l'appareil alors que #9 fait du serveur la source de vérité.

---

## 2. API altimétrie IGN Géoplateforme (RGE ALTI)

Sources : [guide « Calcul altimétrique » (cartes.gouv.fr)](https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/calcul-altimetrique/), [fiche data.gouv.fr](https://www.data.gouv.fr/dataservices/api-geoplateforme-calcul-altimetrique), [liste des ressources](https://data.geopf.fr/altimetrie/resources). L'ancienne URL `geoservices.ign.fr/documentation/services/services-geoplateforme/altimetrie` redirige (301) vers le guide cartes.gouv.fr.

### Endpoints et paramètres

- Points : `https://data.geopf.fr/altimetrie/1.0/calcul/alti/rest/elevation.{json|xml}`
- Profil : `https://data.geopf.fr/altimetrie/1.0/calcul/alti/rest/elevationLine.{json|xml}`, avec `sampling` (*« de 2 à 5 000 »*) et `profile_mode` (`simple` ou `accurate`, qui double l'échantillonnage).
- *« interrogeable en méthodes `GET` et `POST` »*. Paramètres `lon`, `lat`, `resource` (ex. `ign_rge_alti_wld`), `delimiter` (`|`, `;`, `,`), `zonly`, `measures`.
- Les listes `lon`/`lat` sont *« limité[es] à 5 000 »*.
- *« Les altitudes fournies sont arrondies à 2 chiffres après la virgule. »*
- *« Pour un point situé dans une zone non couverte par la donnée, l'altitude renvoyée sera « -99999 ». »* Vérifié le 2026-10-10 : un point à Londres renvoie `-99999.0`.

### Quotas, accès, conditions

- *« Son usage est limité à 5 requêtes par seconde depuis une même adresse IP. »* (guide et data.gouv.fr)
- data.gouv.fr : accès **« Ouvert »**, aucune clé mentionnée, disponibilité annoncée de **« 99.5% »**, producteur IGN (geoplateforme@ign.fr).
- **Vérifié le 2026-10-10** : les requêtes GET et POST répondent `200` **sans clé ni en-tête particulier**.
- Licence : le site est *« sous licence etalab-2.0 »*. Le RGE ALTI est lui aussi diffusé sous etalab-2.0, d'après sa fiche relayée par le [catalogue Google Earth Engine](https://developers.google.com/earth-engine/datasets/catalog/IGN_RGE_ALTI_1M_2_0). Je n'ai pas pu lire la fiche IGN officielle : la page catalogue cartes.gouv.fr est rendue en JavaScript. La Licence Ouverte autorise la réutilisation et le **stockage** à condition de **mentionner la source** (« IGN »). Il n'y a pas de clause de non-stockage comparable à celles de Mapbox.
- Je n'ai trouvé aucune CGU spécifique à l'API au-delà du plafond de 5 req/s.

### Données

- Ressources (`/altimetrie/resources`) : `ign_rge_alti_wld` (*« RGE Alti - France entière - métadonnées statiques »*, emprise de -63° à 45° de longitude, DOM inclus), `ign_rge_alti_par_territoires` (*« RGE Alti 1m - France + DOM par territoire - Source et précision dynamiques »*), plus des ressources LiDAR HD (50 cm, couverture partielle pour l'instant).
- RGE ALTI : **MNT** (terrain nu, sans bâtiments ni arbres) au pas de 1 m. La précision verticale dépend de la source, d'après le descriptif IGN relayé par Earth Engine : **0,2–0,5 m** en LiDAR (zones inondables, littoral, grandes forêts), **0,5–0,7 m** en corrélation d'images, et **environ 7 m** sur les fortes pentes des zones de montagne couvertes par radar (Alpes, Pyrénées, Cévennes, Corse). À vérifier dans le descriptif de contenu IGN.

### Latence mesurée (2026-10-10, POST `elevation.json`, `ign_rge_alti_wld`)

| Points | Latence |
|---|---|
| 3 (GET) | 0,27–0,93 s |
| 100 | 0,56–0,77 s |
| 1 000 | 0,71–0,72 s |
| 5 000 | 2,79 s |

Avec un pas de 20 m, une requête couvre 100 km. Le temps fixe domine jusqu'à environ 1 000 points.

---

## 3. Open-Meteo Elevation API (Copernicus GLO-90)

Sources : [doc Elevation API](https://open-meteo.com/en/docs/elevation-api), [conditions](https://open-meteo.com/en/terms), [prix](https://open-meteo.com/en/pricing), [licence](https://open-meteo.com/en/licence).

- `GET https://api.open-meteo.com/v1/elevation?latitude=…&longitude=…`. *« Up to 100 coordinates can be requested at once. »*
- Données : *« Copernicus DEM 2021 release GLO-90 »*, 90 m, couverture mondiale. La page ne donne aucune précision au-delà de la résolution.
- Quotas gratuits : *« Less than 10'000 API calls per day, 5'000 per hour and 600 per minute »*, 300 000 par mois. *« You may only use the free API services for non-commercial purposes. »* Les offres payantes (Standard 1M/mois, Professional 5M, Enterprise 50M+) ne sont pas chiffrées sur la page. La page de prix ne dit pas si une requête à 100 points compte pour un ou plusieurs appels.
- Licence : *« API data are offered under Attribution 4.0 International (CC BY 4.0) »*. *« You are free to share: copy and redistribute the material »*, donc le stockage est autorisé avec attribution. La doc Elevation exige en plus : *« All users of Open-Meteo data must provide a clear attribution to the Copernicus program. »*
- Latence mesurée le 2026-10-10 : **0,12–0,17 s** pour 100 points. 1 000 points demandent 10 requêtes.
- Pour le projet : l'app ne sera jamais publiée, donc l'usage reste non commercial et le palier gratuit suffit.

---

## 4. Copernicus DEM (source primaire)

Sources : [Copernicus Data Space, COP-DEM](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM), [AWS Open Data](https://registry.opendata.aws/copernicus-dem/).

- *« The Copernicus DEM is provided in 3 different instances: EEA-10, GLO-30 and GLO-90. »* Résolutions de 10, 30 et 90 m.
- *« Absolute vertical accuracy: < 4m (90% linear error) »*. Datum vertical *« EGM2008 (EPSG 3855) »*. Acquisition TanDEM-X entre 2011 et 2015.
- **MNS** : *« represents the surface of the Earth including buildings, infrastructure and vegetation »*. C'est le défaut majeur pour un D+ : la canopée et les toits deviennent du relief.
- Licence : *« The GLO-30 and GLO-90 datasets are available worldwide with a free license »*, avec la mention *« © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved »*.
- AWS : buckets `copernicus-dem-30m` et `copernicus-dem-90m` (`eu-central-1`), *« Cloud Optimized GeoTIFFs »*. GLO-30 Public a une couverture *« limited »*, car certains pays ne sont pas publics.

### DEM hébergé chez nous

- Options : COG Copernicus GLO-30 (France : quelques dizaines de dalles 1°×1°, ordre de grandeur non vérifié), ou RGE ALTI 5 m / 1 m téléchargé depuis la Géoplateforme (volume non vérifié, nettement plus lourd en 1 m).
- Lecture côté serveur : lire un COG par fenêtres avec GDAL ou `geotiff.js`, ou utiliser un moteur dédié. Valhalla `/height` prend un `shape` ou un `encoded_polyline` avec `resample_distance` (*« the distance at which the input polyline is sampled in order to provide uniform distances between samples »*), à partir de *« Amazon Web Services Public Datasets »* ([doc Valhalla](https://valhalla.github.io/valhalla/api/elevation/)).
- Avantages : pas de quota, pas de dépendance réseau externe, latence locale. Inconvénients : stockage de rasters sur le VPS, un service de plus à déployer et surveiller. Avec Copernicus, le biais MNS reste. Avec le RGE ALTI, on retrouve la qualité IGN sans quota, mais au prix de la gestion des données.

---

## 5. Tableau comparatif

| Critère | `elevation(at:)` (Terrain-DEM v1) | IGN Géoplateforme (RGE ALTI) | Open-Meteo (Copernicus GLO-90) | DEM hébergé (Copernicus GLO-30 ou RGE ALTI) |
|---|---|---|---|---|
| **Type de modèle** | Non documenté, sources multiples | **MNT** (terrain nu) | **MNS** (arbres, bâtiments) | MNS (Copernicus) ou MNT (RGE ALTI) |
| **Résolution** | Jusqu'à z14 (≈ 3,4 m/px à 45° N, calculé), plus grossière si dézoomé | 1 m | 90 m | 30 m ou 1–5 m |
| **Précision verticale** | Non documentée | 0,2–0,7 m, ≈ 7 m sur fortes pentes de montagne (radar) | < 4 m LE90, plus le biais MNS | Idem source |
| **Couverture** | Mondiale, mais **seulement la zone visible à l'écran** | France + DOM (`-99999` ailleurs) | Mondiale | Selon les dalles téléchargées |
| **Coût** | Inclus dans les MAU du Maps SDK (probable, non confirmé) | Gratuit | Gratuit en non commercial | Stockage + exploitation |
| **Quotas** | Aucun par requête | 5 req/s par IP, 5 000 points/requête | 600/min, 5 000/h, 10 000/jour, 100 points/requête | Aucun |
| **Stockage du résultat** | Interdit par les Product Terms (§1.6, §1.9(v)), déviation possible (#12) | **Autorisé** (Etalab 2.0, mention « IGN ») | **Autorisé** (CC BY 4.0, mention Open-Meteo + Copernicus) | Autorisé (licence Copernicus ou Etalab) |
| **Appel depuis** | App uniquement (`@MainActor`) | App ou API (sans clé) | App ou API | API |
| **Latence (mesurée le 2026-10-10)** | Instantanée (tuiles déjà chargées) | 0,6–0,8 s jusqu'à 1 000 pts, 2,8 s à 5 000 | 0,12–0,17 s par 100 pts | Locale, quelques ms (estimation) |
| **D+ mesuré (100 pts) Paris / Fontainebleau** | Non testé | 29 m / 44 m (brut), 22 / 37 m (seuil 2 m) | 97 m / 106 m (brut), 86 / 99 m (seuil 2 m) | Non testé |

---

## 6. Densité d'échantillonnage et filtrage pour un D+ fiable

### Pourquoi ré-échantillonner

Le tracé Directions (`polyline6`, `overview=full`) a des sommets là où la route change de direction. Une longue ligne droite peut avoir des sommets espacés de plusieurs centaines de mètres et passer par-dessus une bosse. Il faut donc ré-échantillonner le tracé à **pas constant** avant de demander les altitudes. C'est ce que font les moteurs de routage :
- GraphHopper ([`config-example.yml`](https://raw.githubusercontent.com/graphhopper/graphhopper/master/config-example.yml)) : *« set the distance (in meters) at which elevation samples should be taken on long edges »* → `long_edge_sampling_distance: 60`. Lissage proposé : `moving_average` avec `window_size: 150` (*« will reveal values not affected by outliers and realistic slopes and total altitude values »*), ou `ramer` avec `max_elevation: 5` (*« removes elevation fluctuations up to max_elevation »*).
- Valhalla `/height` : `resample_distance` pour des échantillons à distance uniforme.

### Mesures (2026-10-10, segments droits, même calcul pour chaque source)

D+ « brut » : somme des différences positives entre points consécutifs, comme `compute-metrics` aujourd'hui. D+ « seuil 2 m » : hystérésis, où une montée n'est comptée que si l'altitude dépasse de 2 m le dernier point de référence (ce point est aussi mis à jour par une descente de 2 m).

| Segment | Points (pas) | Source | D+ brut | D+ seuil 2 m |
|---|---|---|---|---|
| Chamonix → Plan de l'Aiguille, 3,2 km | 100 (32 m) | IGN | 1 369 | 1 363 |
| idem | 1 000 (3,2 m) | IGN | 1 394 | 1 366 |
| idem | 5 000 (0,6 m) | IGN | 1 418 | 1 367 |
| idem | 100 (32 m) | Open-Meteo | 1 344 | — |
| Paris Concorde → Bastille, 3,8 km | 100 (38 m) | IGN | 29 | 22 |
| idem | 1 000 (3,8 m) | IGN | 51 | 20 |
| idem | 100 (38 m) | Open-Meteo | 97 | 86 |
| Forêt de Fontainebleau, 5,0 km | 100 (50 m) | IGN | 44 | 37 |
| idem | 1 000 (5 m) | IGN | 51 | 37 |
| idem | 100 (50 m) | Open-Meteo | 106 | 99 |

Constats :
- **Sans filtre, le D+ dépend de la densité** : il croît avec le nombre de points (+75 % dans Paris entre 38 m et 3,8 m de pas) parce que le bruit du MNT s'additionne.
- **Avec un seuil de 2 m, il est stable** entre 0,6 m et 50 m de pas (écarts de 0 à 4 m).
- **Le MNS Copernicus surévalue fortement** en ville et en forêt, même filtré (×4 dans Paris, ×2,7 à Fontainebleau par rapport à l'IGN filtré). Ce biais ne disparaît pas au filtrage : un bâtiment ou une lisière fait plus de 2 m.

### Recommandation

- **Pas de 20 m** le long du tracé : sous le pas des moteurs de routage (60 m) et assez fin pour ne pas couper une bosse. 5 000 points (une requête IGN) couvrent alors 100 km. Au-delà, on découpe en plusieurs requêtes ou on passe à 25–30 m.
- **Seuil d'hystérésis de 2 m** sur l'altitude avant de cumuler le D+. C'est l'équivalent simple du `ramer` de GraphHopper. Il est indépendant de la densité dans nos mesures.
- Stocker les points ré-échantillonnés avec leur altitude : ils serviront au profil altimétrique, sans nouvel appel.

---

## 7. Cohérence avec `compute-metrics` (Activities)

`packages/core/src/activities/domain/compute-metrics.ts`, lu sur `main` (0008c01) :

1. **Pas de lissage.** Le code cumule chaque `delta > 0` brut. Son commentaire le dit (*« no smoothing beyond the moving speed threshold »*), alors qu'ADR-019 §5 étape 4 annonce *« elevation gain (smoothed altitude) »* et prévoit de calibrer plus tard (*« Algorithms […] to be calibrated on real traces »*). Le seul seuil existant (`movingSpeedThresholdMs = 0.5`) porte sur la vitesse, pas sur l'altitude.
2. **Il dépend des horodatages.** La boucle fait `if (segmentTimeS <= 0) continue;` **avant** d'ajouter la distance et le D+. Un tracé d'Itinéraire n'a pas de temps : avec des `timestampMs` identiques, `computeMetrics` renvoie `distanceM = 0` et `elevationGainM = 0`. Lui fabriquer des horodatages serait un contournement fragile.
3. `cleanTrace` ne touche pas l'altitude (précision horizontale et sauts de vitesse seulement).

Conséquence : pour que « le serveur recalcule avec la même fonction » (#9) ait un sens, il faut **extraire une fonction pure sans notion de temps**, par exemple `computeDistanceAndElevationGain(points, { elevationThresholdM })`, appelée par `computeMetrics` pour les Activities et directement pour les Itinéraires. Le seuil de 2 m s'applique alors aux deux. Pour les Activities, c'est un changement de comportement : le D+ des traces GPS baissera, puisque le bruit GPS et baromètre est aujourd'hui compté en entier. Les sources restent différentes (altitude de la montre contre MNT), donc les chiffres ne seront jamais identiques entre un Itinéraire et la sortie qui le suit. La cohérence porte sur la **méthode**, pas sur la valeur.

---

## 8. Recommandation

**Source enregistrée : API IGN Géoplateforme, appelée par le serveur.**

1. À l'enregistrement, l'app envoie le **tracé 2D** (comme prévu dans #9 si la source est côté serveur).
2. L'API ré-échantillonne à 20 m, demande les altitudes à l'IGN (`ign_rge_alti_wld`, POST, 1 requête jusqu'à 100 km), puis calcule distance et D+ avec la fonction partagée (seuil 2 m). Elle stocke les points ré-échantillonnés avec leur altitude et la source utilisée.
3. **Hors France** (`-99999` sur une partie des points) : repli sur **Open-Meteo** pour ces points, avec la source marquée sur l'Itinéraire. On sait que le D+ sera surévalué en forêt et en ville. Si tout l'Itinéraire est hors couverture, on peut aussi afficher « D+ approximatif ».
4. Attribution à afficher là où le D+ et le profil sont montrés : « Altitudes : IGN » (et « Open-Meteo, Copernicus DEM » en cas de repli).

**Estimation pendant l'édition : le même calcul, exposé par l'API.**

- Un endpoint de prévisualisation (tracé 2D → distance, D+, profil) appelé **à la fin du glissement**, une fois la réponse Directions reçue, et pas à chaque image. Il utilise le même code, donc **l'estimation affichée et le chiffre enregistré sont identiques**. Seule la distance peut s'afficher immédiatement côté app.
- Coût en latence : environ 0,6–0,8 s (IGN) plus un aller-retour vers l'API, après la requête Directions. C'est acceptable pour un chiffre qui se met à jour au relâchement, contrairement au tracé, que #9 veut immédiat. Pendant l'attente, l'app garde l'ancienne valeur, marquée comme en cours de calcul.
- Quota : 5 req/s par IP, et toutes les requêtes partent de l'IP du VPS. Pour un projet non publié, c'est large, mais il faut un petit cache ou une file si plusieurs athlètes éditent en même temps.

**Pourquoi pas les autres :**
- `elevation(at:)` : limité à l'écran, précision liée au zoom et non documentée, disponible seulement sur l'appareil. On peut s'en servir plus tard pour un détail visuel (altitude sous le doigt), pas pour le D+.
- Open-Meteo en source principale : le MNS double ou triple le D+ hors montagne nue. On le garde en repli.
- DEM hébergé : pas justifié tant que l'IGN répond, sans clé, à ces volumes. À reconsidérer si le quota de 5 req/s ou la disponibilité posent problème. Le RGE ALTI téléchargé serait alors préférable à Copernicus.

**Alternative à trancher avec l'humain** : faire appeler l'IGN **directement par l'app** pendant l'édition (sans clé, quota de 5 req/s par IP de l'appareil, un aller-retour de moins), puis porter le ré-échantillonnage et le seuil en Swift. Le prix est une **double implémentation** de l'algorithme, avec un risque d'écart entre l'estimation et le chiffre enregistré. Je recommande l'endpoint API.

### Points ouverts

- Extraire la fonction distance + D+ et appliquer le seuil de 2 m aux Activities : changement de comportement à décider (ADR-019 « smoothed altitude »).
- Repli hors France : Open-Meteo, ou « D+ inconnu » ?
- À confirmer : précision RGE ALTI dans le descriptif IGN officiel (lu ici via Earth Engine), couverture MAU des tuiles DEM, comptage des appels Open-Meteo multi-points.
- `elevation(at:)` et `TileStore` hors écran : non testé sur appareil, la conclusion repose sur le commentaire du code.

---

## Annexe : méthode des mesures

Script Python jetable, non commité. Il trace des segments droits entre deux coordonnées, découpés en N points équidistants (interpolation linéaire en lat/lon). Requêtes POST vers `elevation.json` (IGN, `resource=ign_rge_alti_wld`, `zonly=true`, `delimiter=|`) et GET vers `api.open-meteo.com/v1/elevation`. La latence est le temps de `urlopen` jusqu'à la fin de la lecture JSON, sur une connexion résidentielle en France, le 2026-10-10. Les segments droits ne suivent pas de vrais chemins : ils servent à comparer les sources et les densités entre elles, pas à prédire le D+ d'un Itinéraire réel.

Coordonnées : Chamonix (45.9237, 6.8694) → Plan de l'Aiguille (45.8986, 6.8889) ; Concorde (48.8656, 2.3212) → Bastille (48.8532, 2.3692) ; Fontainebleau (48.4300, 2.6300) → (48.4000, 2.6800).
