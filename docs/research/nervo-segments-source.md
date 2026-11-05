# Recherche : source mondiale des Segments créés par Nervo

- **Ticket** : [#224 Source mondiale des Segments créés par Nervo](https://github.com/echimine/clone-strava/issues/224) (carte wayfinder [#223 Segments et Records dans l'app](https://github.com/echimine/clone-strava/issues/223))
- **Date** : 2026-11-05
- **Contexte** : la carte #223 a décidé que des Segments sont créés **par Nervo, pour le monde entier**, en plus de ceux créés par les athlètes. Ce sont des Segments ordinaires (toujours publics, créateur jamais affiché), seulement pour les sports avec carte (`run`, `ride`, `walk`, `hike`). Le schéma actuel (`packages/db/src/schema/segments.ts`) a `name`, `sport_type_code`, `path`, `start_point`, `end_point`, `distance_m`, `avg_grade`, avec un index GiST sur `path` et sur `start_point` (ADR-017). L'appariement est décrit par ADR-019 §8 : *« Search for candidate segments of the same sport near the route (GiST index), then check that the route actually follows the segment from end to end »*.
- **Question** : d'où peuvent venir ces Segments, sous quelle licence, combien, comment les produire, ce que ça coûte en base et à l'appariement, et quoi faire pour la course, la marche et la randonnée ?
- **Hors question** : copier les Segments de Strava ou d'un site de cols sous licence fermée (Climbfinder, etc.). C'est exclu d'office ; Climbfinder n'est cité ci-dessous **que** pour un ordre de grandeur (un total affiché publiquement), aucune de ses données n'est reprise.
- **Sources** : wiki OpenStreetMap, API taginfo (planète et instances Geofabrik par pays), texte de l'ODbL 1.0, lignes directrices de l'OSM Foundation (Community Guidelines, Attribution Guideline), licence Copernicus WorldDEM-30, registre AWS Open Data, catalogue NASA Earthdata (SRTM), GeoNames, manuel Garmin Edge (ClimbPro), page d'aide Strava (catégories de montée), code de la crate `navigo`, documentation PostGIS et Mapbox. Tout a été lu le **2026-11-05**. Les citations sont verbatim (en anglais). Les comptages taginfo datent des exports du **2026-11-04**.

> Vocabulaire : « Segment », « Effort », « Activity » sont les termes du glossaire (`CONTEXT.md`). « Montée » désigne une portion de route ou de chemin qui monte, candidate à devenir un Segment.

---

## TL;DR

1. **La seule source mondiale ouverte de géométries de routes et chemins est OpenStreetMap**, sous **ODbL 1.0**. Rien d'autre ne donne le tracé d'une route avec son nom. OSM n'a pas de « montées » prêtes à l'emploi : `mountain_pass=yes` marque un **point** (le sommet d'un col, 40 256 objets dans le monde, 4 166 en France), `incline=*` est surtout `up`/`down` sans valeur et ne couvre que des tronçons raides isolés. Il faut **calculer** les montées : tracé OSM + altitude d'un **modèle numérique de terrain (MNT/MNS)**.
2. **Altitude** : **Copernicus GLO-30** (30 m, mondial, gratuit, réutilisation commerciale permise, deux mentions obligatoires) en source principale ; **SRTM GL1** (30 m, 60° N–56° S, *« openly shared, without restriction »*) en secours. Copernicus est un **MNS** (*« buildings, infrastructure and vegetation »*) : la recherche #14 a mesuré un D+ ×2,4 en forêt et ×3,3 en ville. Lissage + seuil d'hystérésis obligatoires, et un MNT national là où il existe (IGN RGE ALTI pour la France). **FABDEM** (Copernicus sans arbres ni bâtiments) est **non commercial** : exclu.
3. **Détection** : les critères publics de Garmin (ClimbPro) et Strava convergent : *score = longueur (m) × pente (%)*, catégories 4/3/2/1/HC au-delà de 8 000 / 16 000 / 32 000 / 64 000 / 80 000 ; Garmin exige en plus 500 m et 3 % de pente moyenne au minimum. Règle proposée pour le vélo : ≥ 500 m, ≥ 3 % et score > 8 000 (Cat. 4). Ce sont des critères, pas des données : on peut les reprendre. Il n'existe pas d'outil ouvert « tout-en-un » OSM + MNT → montées nommées ; `navigo` (Rust, MIT) implémente la même règle sur une trace GPS. Il faut écrire le générateur.
4. **ODbL** : une base de Segments **tirée systématiquement** d'OSM est une **Derivative Database** (ce n'est ni « insubstantial » ni une « trivial transformation », puisque l'altitude vient d'une source externe). Son usage public dans l'app (carte, classement = Produced Work) déclenche le **partage à l'identique** : il faut **attribuer** OpenStreetMap là où les Segments sont montrés et **offrir gratuitement** la base dérivée (ou la méthode, l'algorithme, plus les données ajoutées) sous ODbL. **Les Efforts, traces et classements ne sont pas contaminés** (cas « traffic data from in-car GPS » des lignes directrices OSMF). **Les Segments créés par les athlètes** cohabitent avec ceux d'OSM dans le même type de donnée : le partage à l'identique peut les atteindre. Le plus simple est de l'accepter (les Segments sont publics de toute façon).
5. **Volumes réalistes** (ordre de grandeur, à confirmer par un pilote) : Climbfinder affiche publiquement **20 458 montées en France** et **90 808 en Europe** (longueur moyenne 3,5 km, 185 m de D+). Avec des seuils comparables, Nervo peut viser **10 000 à 30 000 montées vélo en France**, de l'ordre de **10⁵ en Europe** et **quelques 10⁵ à 10⁶ dans le monde**. Stockage : ~2–3,5 Ko par Segment simplifié, soit **~0,3 Go pour 100 000** et **~3 Go pour 1 million**, et ~50 Mo par index GiST par million de lignes (calculs, §7).
6. **Appariement** : la densité ajoutée est faible (France, au rythme des montées connues : ≈ 1 pour 27 km² en moyenne). Pour une sortie de 60 km, le filtre GiST renvoie quelques dizaines de candidats au plus en montagne, et le test exact n'en garde que ceux que le tracé longe. Découper le tracé de l'Activity avec `ST_Subdivide` avant la recherche réduit encore les faux positifs de la boîte englobante. Le coût est négligeable devant le traitement de l'Activity.
7. **Production** : un **générateur hors ligne** (script dans `scripts/`), lancé **pays par pays** sur un poste ou une machine louée, pas sur le VPS : extrait OSM Geofabrik (France 5,1 Go, Europe 35 Go, planète 96 Go) → routes et chemins → altitude échantillonnée tous les ~25 m → lissage + hystérésis → détection → dédoublonnage → nommage (nom du col, sinon nom/numéro de route + « depuis <lieu> ») → **export** (fichier ODbL publié) → **chargement idempotent** en prod (clé source stable) → **rétro-appariement** par le worker. Relances ponctuelles (annuelles) qui **ajoutent** des Segments et n'en modifient jamais (modifier un tracé est hors carte).
8. **Course, marche, randonnée** : rien d'équivalent aux cols ne se trouve tout fait dans OSM (`route=running` : 1 368 relations dans le monde, 222 en France). Recommandation : **randonnée** = montées vers un sommet nommé (`natural=peak` avec `name`, 697 354 dans le monde) sur chemins `sac_scale` ≤ `demanding_mountain_hiking`, avec un seuil de D+ ; **course** = montées courtes en ville (score Garmin ≥ 1 500, 500 m min.) sur rues et chemins accessibles à pied, en petit nombre, et reprise des montées vélo accessibles à pied ; **marche** = **pas de Segments Nervo**, ceux des athlètes suffisent. Un même tracé pour deux sports = deux lignes `segment` avec le schéma actuel : à trancher à la carte.

---

## 1. Ce qu'OpenStreetMap contient vraiment

### 1.1 Cols : `mountain_pass=yes`

[Wiki, `Tag:mountain_pass=yes`](https://wiki.openstreetmap.org/wiki/Tag:mountain_pass%3Dyes) : *« Marks the highest point of a mountain road, railway or path as it passes over a crest. »* Le tag s'utilise sur des **nœuds** (pas sur des ways). Combinaisons utiles : `name=*`, `ele=*`. Le wiki renvoie vers `natural=saddle` (*« The lowest point along a ridge or between two mountain tops »*), qui est un objet différent. La page est marquée *« This tag page is a stub »*.

Comptages [taginfo](https://taginfo.openstreetmap.org/tags/mountain_pass=yes) (planète, données du 2026-11-04) :

| Tag | Total | Nœuds | Ways | Relations |
|---|---:|---:|---:|---:|
| `mountain_pass=yes` | 40 256 | 40 045 | 207 | 4 |
| `natural=saddle` | 81 094 | 81 027 | 62 | 5 |
| `natural=peak` | 1 113 889 | 1 113 753 | 110 | 26 |

Combinaisons de `mountain_pass=yes` ([taginfo, combinations](https://taginfo.openstreetmap.org/tags/mountain_pass=yes#combinations)) : `name` 34 543, `ele` 30 171, `natural=saddle` 23 703, `rtsa_scale` 11 149, `westra_ref` 10 364. **Plus d'un quart des cols OSM sont des cols de randonnée alpine**, pas des cols routiers : `rtsa_scale` est la *« Russian Hiking Sports Association (RTSA) mountain pass difficulty classification. Widespread in the countries of the former USSR »* (description wiki de la clé, via l'API taginfo `key/wiki_pages`). Un col n'est utile au vélo que si son nœud appartient à une route.

Par pays ([taginfo Geofabrik](https://taginfo.geofabrik.de/), exports du 2026-11-04) :

| Pays | `mountain_pass=yes` | `natural=saddle` | ways avec `incline` |
|---|---:|---:|---:|
| France | 4 166 | 7 209 | 152 453 |
| Italie | 4 571 | 8 796 | 165 967 |
| Espagne | 3 889 | 19 218 | 63 930 |
| Suisse | 871 | 2 679 | 55 828 |
| Belgique | 55 | 52 | 20 566 |

Quels cols sont sur une route ? Requête Overpass sur la **Suisse** (2026-11-05, `out count` des nœuds `mountain_pass=yes` membres d'une way) : **181** des 871 cols sont sur une way `highway` de `motorway` à `service` (routes carrossables), **479** sur une way `track`/`path`/`footway`/`bridleway`/`cycleway`/`steps`, le reste sur aucune des deux. **Environ un col suisse sur cinq est routier.** La même requête sur la France n'a pas abouti : les serveurs publics Overpass étaient saturés (*« This Overpass API server is currently at capacity »*). Le pilote la refera sur un extrait local.

Conséquence : les cols ne donnent que des **ancres** (un sommet nommé avec son altitude). La montée elle-même (où elle commence, sa longueur, sa pente) doit être calculée, et la majorité des montées intéressantes ne finissent pas à un col (la Belgique a 55 cols OSM ; Climbfinder y affiche 8 790 montées).

### 1.2 Pente : `incline=*`

[Wiki, `Key:incline`](https://wiki.openstreetmap.org/wiki/Key:incline) : *« Indicates a way's grade, slope, or incline. »* Convention : *« As one moves forward on a way, a positive incline gets higher, and a negative incline gets lower. »* La valeur doit être *« the practical maximum incline on the steep section »*, pas *« the average incline between the nodes »*, et on coupe la way aux extrémités du tronçon raide. *« Ways with a steepness of under 10 % are seldom signposted »*.

Taginfo : 1 785 459 ways avec `incline` dans le monde ; valeurs les plus fréquentes `up` (881 481) et `down` (641 605), puis `0%` (96 879), `10%` (20 286), `15%` (10 621). **Environ 85 % des valeurs n'ont pas de chiffre** (`up` et `down` font 1 523 086 des 1 792 519 objets), et les autres décrivent une pente maximale locale, pas une montée. `incline` ne peut servir qu'à **contrôler** une pente calculée, pas à trouver des montées.

Il n'existe pas de tag de montée : la clé `climb` a 33 usages dans le monde.

### 1.3 Itinéraires nommés : relations `route=*`

[Wiki, `Tag:route=bicycle`](https://wiki.openstreetmap.org/wiki/Tag:route%3Dbicycle) : *« Cycle routes or bicycle route are named or numbered or otherwise signed routes. »* Réseaux `icn`/`ncn`/`rcn`/`lcn` (international, national, régional, local). Les membres sans rôle sont *« The ways making up the route. »*

| Relations | Monde | France | Suisse | Belgique |
|---|---:|---:|---:|---:|
| `route=bicycle` | 141 699 | 8 718 | 1 038 | 13 270 |
| `route=mtb` | 21 551 | 3 457 | 550 | 477 |
| `route=hiking` | 272 941 | 45 603 | 26 238 | 4 808 |
| `route=foot` | 69 466 | — | — | — |
| `route=running` | 1 368 | 219 | 90 | 55 |
| `route=fitness_trail` | 991 | 186 | 341 | 20 |

Ces itinéraires font des dizaines ou centaines de kilomètres : ce ne sont pas des Segments, mais ils servent à **départager** (une montée sur un itinéraire balisé est plus fréquentée) et à **nommer**.

### 1.4 Réseau et difficulté des chemins

Planète : `highway=path` 16,6 M ways, `highway=track` 30,2 M, `highway=cycleway` 2,26 M, `highway=steps` 2,15 M. [Wiki, `Key:sac_scale`](https://wiki.openstreetmap.org/wiki/Key:sac_scale) : *« A difficulty rating scheme for hiking trails. »* Valeurs : `hiking` (*« Trail well cleared or with rather minor obstacles like roots »*, 526 705 ways), `mountain_hiking` (305 835), `demanding_mountain_hiking` (59 167), `alpine_hiking` (*« Use of hands needed in order to advance in certain places (UIAA grade I) »*, 18 237).

[Wiki, `Tag:leisure=track`](https://wiki.openstreetmap.org/wiki/Tag:leisure%3Dtrack) : *« A track for running, cycling and other non-motorised racing »* ; *« It is preferable to map running tracks as multipolygons »*. Une piste d'athlétisme est donc le plus souvent une **surface** fermée, pas une ligne avec un départ et une arrivée : inutilisable telle quelle comme Segment.

### 1.5 Autres sources ouvertes

- **GeoNames** ([about](https://www.geonames.org/about.html)) : *« licensed under a Creative Commons Attribution 4.0 License »*, *« over 13 million unique features »*. Code `PASS` : *« a break in a mountain range or other high obstruction, used for transportation from one side to the other »* ([codes](https://www.geonames.org/export/codes.html)). Comptage sur les exports `FR.zip` et `CH.zip` du 2026-11-05 : **751 `PASS` en France, 1 786 en Suisse**, des **points** sans tracé. Utile pour nommer sans OSM, pas pour tracer.
- **Bases nationales** : en France, la BD TOPO et le RGE ALTI de l'IGN sont sous licence Etalab 2.0 (attribution seule, pas de partage à l'identique ; voir la recherche [#14](https://github.com/echimine/clone-strava/blob/research/itinerary-elevation-source/docs/research/itinerary-elevation-source.md)). Elles ne couvrent qu'un pays. Pour le monde, il n'y a qu'OSM.

---

## 2. Licence ODbL et ce qu'elle impose

### 2.1 Le texte ([ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/))

- **Derivative Database** : *« Means a database based upon the Database, and includes any translation, adaptation, arrangement, modification, or any other alteration of the Database or of a Substantial part of the Contents. This includes, but is not limited to, Extracting or Re-utilising the whole or a Substantial part of the Contents in a new Database. »*
- **Produced Work** : *« a work (such as an image, audiovisual material, text, or sounds) resulting from using the whole or a Substantial part of the Contents (via a search or other query) from this Database, a Derivative Database, or this Database as part of a Collective Database. »*
- **Substantial** : *« The repeated and systematic Extraction or Re-utilisation of insubstantial parts of the Contents may amount to the Extraction or Re-utilisation of a Substantial part of the Contents. »*
- **§3.1** : *« These rights explicitly include commercial use »*.
- **§4.3** (Produced Work) : *« if you Publicly Use a Produced Work, You must include a notice associated with the Produced Work reasonably calculated to make any Person that uses, views, accesses, interacts with, or is otherwise exposed to the Produced Work aware that Content was obtained from the Database »*.
- **§4.4 a/c** (partage à l'identique) : *« Any Derivative Database that You Publicly Use must be only under the terms of: i. This License »* ; *« A Derivative Database is Publicly Used and so must comply with Section 4.4. if a Produced Work created from the Derivative Database is Publicly Used. »*
- **§4.5 b/c** : *« Using this Database, a Derivative Database, or this Database as part of a Collective Database to create a Produced Work does not create a Derivative Database for purposes of Section 4.4 »* ; *« Use of a Derivative Database internally within an organisation is not to the public »*.
- **§4.6** : *« If You Publicly Use a Derivative Database or a Produced Work from a Derivative Database, You must also offer to recipients of the Derivative Database or Produced Work a copy in a machine readable form of: a. The entire Derivative Database; or b. A file containing all of the alterations made to the Database or the method of making the alterations to the Database (such as an algorithm), including any additional Contents »* ; *« free of charge if distributed over the internet »*.

### 2.2 Les lignes directrices de l'OSMF

- [Substantial](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Substantial_-_Guideline) : non substantiel = *« Less than 100 Features »* ou la zone d'*« up to 1,000 inhabitants »*, *« provided that the extraction is one-off »* ; *« we regard repeated small extractions as one big extraction! »*. Une extraction mondiale de routes et de cols est **substantielle**.
- [Trivial Transformations](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Trivial_Transformations_-_Guideline) (encore *« at the proposal stage »*) : les transformations purement algorithmiques ne sont « triviales » que *« if they are driven by OSM data only »* et *« provided that no other source of data is involved »*. Une montée calculée avec un **MNT externe** n'en relève pas.
- [Produced Work](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Produced_Work_-_Guideline) : *« If the published result of your project is intended for the extraction of the original data, then it is a database and not a Produced Work. »* Et : *« if you publish a produced work, the underlying database has to be published as well »*.
- [Collective Database](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Collective_Database_Guideline_Guideline) : des données OSM et non-OSM sont « indépendantes » *« so long as the data used for a particular data type is either all OSM or all non-OSM within the same regional cut »*. Exemple explicite : *« You generate traffic data from in-car GPS information and store and use the location information from your traffic data in a database that also contains OSM data. […] Your location and traffic information is not subject to share-alike. »*
- [Horizontal Map Layers](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Horizontal_Map_Layers_-_Guideline) : *« If you use OpenStreetMap data along with non-OpenStreetMap data for a given Feature Type, then the share-alike condition would apply »*. L'exemple des restaurants ajoutés *« only those restaurants not present in the OpenStreetMap layer »* montre qu'un **complément dédoublonné** est une interaction.
- [Attribution Guideline](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines) (2021) : *« Attribution must be to “OpenStreetMap” »*, avec un lien vers `openstreetmap.org/copyright` ; pour une carte interactive, *« the credit should typically appear in a corner of the map »*, ou *« on a splash screen or pop-up shown when a user starts the app »* ; pour une base : *« You must include attribution to OpenStreetMap and either the text of the ODbL or a link to it as part of the database »*.

### 2.3 Application aux Segments de Nervo

| Objet | Statut ODbL | Obligation |
|---|---|---|
| Segments créés par Nervo (tracé OSM + pente Copernicus + nom OSM) | Derivative Database, utilisée publiquement | ODbL sur ces Segments ; **offrir gratuitement** la base (ou la méthode + les données ajoutées) ; mention ODbL dans le fichier |
| Carte, détail d'un Segment, classement affichés dans l'app | Produced Work | **Attribution** « © OpenStreetMap » avec lien `openstreetmap.org/copyright` |
| Efforts, traces des Activities, classements | Données non-OSM d'un autre type (cas « in-car GPS ») | Aucune : pas de partage à l'identique |
| Segments créés par les athlètes | Même type de donnée que les Segments Nervo dans la même zone | **Risque** de partage à l'identique (§2.2, « all OSM or all non-OSM ») ; certain si on dédoublonne les uns contre les autres |

Points pratiques :

- **Attribution dans l'app** : la carte Mapbox affiche déjà OpenStreetMap. Mapbox : *« You must properly attribute and link Mapbox and OpenStreetMap when using the Mapbox Streets tileset »*, et sur iOS *« Maps that use the Mapbox Maps SDK for iOS will include an information button that reveals an action sheet when tapped »* ([attribution Mapbox](https://docs.mapbox.com/help/dive-deeper/attribution/)). Cette mention couvre le fond de carte, pas forcément une liste de Segments sans carte. Ajouter une ligne « Données © OpenStreetMap » au détail des Segments créés par Nervo, ou un écran « Sources des données » joignable depuis les réglages (forme admise par l'Attribution Guideline). Ce n'est pas afficher le créateur : c'est créditer une source.
- **Offrir la base** (§4.6) : le plus simple est de publier un **fichier** (GeoJSON ou GeoPackage) des Segments créés par Nervo, sans aucune donnée d'athlète, avec la mention ODbL, à une URL stable, régénéré à chaque production. L'alternative (b), publier le générateur et la liste des sources, est permise mais oblige à rendre le script public.
- **Segments des athlètes** : deux voies. (A) **Accepter** que tous les Segments (tracé, nom, sport, distance, pente, sans créateur) soient offerts sous ODbL : ils sont publics dans l'app de toute façon. (B) Les tenir **strictement indépendants** (aucun dédoublonnage, aucune référence croisée) et soutenir qu'ils forment un type de donnée distinct : lecture défendable mais non couverte par une ligne directrice. Recommandation : **(A)**.
- **Ne pas** caler un Segment d'athlète sur le tracé OSM (accrochage aux routes) : il deviendrait lui-même dérivé d'OSM.
- Le fait que l'app ne soit pas publiée (mémoire du projet) ne change rien au principe : l'obligation naît dès l'usage public.

---

## 3. Altitude : MNT ouverts

### 3.1 Copernicus DEM GLO-30 / GLO-90

[Registre AWS Open Data](https://registry.opendata.aws/copernicus-dem/) : *« The Copernicus DEM is a Digital Surface Model (DSM) which represents the surface of the Earth including buildings, infrastructure and vegetation. »* *« GLO-90 provides worldwide coverage at 90 meters. »* *« GLO-30 Public provides limited worldwide coverage at 30 meters because a small subset of tiles covering specific countries are not yet released to the public. »* *« Data is provided as Cloud Optimized GeoTIFFs. »* Seaux `copernicus-dem-30m` et `copernicus-dem-90m`. Le fichier `tileList.txt` du seau 30 m liste **26 450 tuiles** de 1°×1° ; deux tuiles alpines et franciliennes pèsent 42 et 46 Mo (mesuré).

[Licence COP-DEM-GLO-30](https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf) :

- Art. 4 : droits de *« reproduction; distribution; communication to the General Public; adaptation, modification and combination with other data and information »*.
- Art. 5 : *« The use rights granted under this licence are free of charge to the User. »* Aucune restriction d'usage commercial n'est écrite.
- Art. 6(b) : *« Where the Copernicus WorldDEM-30 data have been adapted or modified, the User shall provide the following notice: "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved" »*.
- Art. 6(c) : la phrase *« The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30 »* doit figurer dans la notice qui couvre la diffusion.

Pas de partage à l'identique : Copernicus n'ajoute que deux mentions.

### 3.2 SRTM GL1

[NASA Earthdata, SRTMGL1 v003](https://www.earthdata.nasa.gov/data/catalog/lpcloud-srtmgl1-003) : *« This dataset is openly shared, without restriction, in accordance with the EOSDIS Data Use and Citation Guidance. »* Résolution *« 30 Meters x 30 Meters »*, couverture *« all land between 60° N and 56° S latitude »*. [USGS](https://www.usgs.gov/centers/eros/science/usgs-eros-archive-digital-elevation-shuttle-radar-topography-mission-srtm-1) : *« Some tiles may still contain voids. »* Données de 2000. Utile en secours (tuiles GLO-30 non publiées), sans mention imposée.

### 3.3 Biais de surface et MNT nationaux

Copernicus mesure le dessus des arbres et des toits. La recherche [#14](https://github.com/echimine/clone-strava/blob/research/itinerary-elevation-source/docs/research/itinerary-elevation-source.md) a mesuré, à 100 points, un D+ **×3,3 en ville** (Paris) et **×2,4 en forêt** (Fontainebleau) par rapport à l'IGN, et montré qu'un **ré-échantillonnage tous les ~20 m avec un seuil d'hystérésis de 2 m** stabilise le D+. Sur une route de col, l'écart entre MNS et MNT est faible (la chaussée est dégagée) ; en forêt et en ville, il fausse la pente moyenne et crée de fausses montées. Donc :

- lisser et appliquer l'hystérésis avant toute détection ;
- utiliser un MNT national quand il existe (France : RGE ALTI 1 m, Etalab 2.0, voir #14) ;
- caler les extrémités sur `ele=*` d'OSM quand le col ou le sommet en a un (30 171 cols et 783 941 sommets ont `ele`).

**FABDEM** (*« Forest And Buildings removed Copernicus DEM »*, [Fathom](https://www.fathom.global/product/global-terrain-data-fabdem/)) serait idéal techniquement, mais *« The FABDEM dataset is licensed under a Creative Commons "CC BY-NC-SA 4.0" license »* et *« FABDEM may not be used for commercial purposes »* (fiche du [catalogue communautaire GEE](https://gee-community-catalog.org/projects/fabdem/), qui renvoie au [jeu de l'université de Bristol](https://data.bris.ac.uk/data/dataset/s5hqmjcdj8yo2ibzi9b4ew3sn) ; la page de Bristol n'a pas répondu le 2026-11-05 et la page produit de Fathom ne donne pas la licence). Exclu sans licence commerciale de Fathom. **Open-Meteo** (Copernicus GLO-90 via API) est gratuit seulement pour un usage non commercial (#14) : exclu pour une production en masse.

---

## 4. Détecter une montée : critères publics et outils ouverts

### 4.1 Critères

- **Garmin ClimbPro** ([manuel Edge 1050](https://www8.garmin.com/manuals/webhelp/GUID-08ACA9FC-DEE6-4C8D-8A95-F62181C512E9/EN-US/GUID-EBAEC138-B55A-4730-8C10-DF21A40302A9.html)) : *« A climb must have a length of at least 500 meters and an average grade of at least 3 percent to be considered a climb. »* *« Climb categories are determined by climb score, which is calculated using the grade multiplied by the length of the climb. »* Seuils : HC *« Greater than 80,000 »*, Cat. 1 *« Greater than 64,000 »*, Cat. 2 *« Greater than 32,000 »*, Cat. 3 *« Greater than 16,000 »*, Cat. 4 *« Greater than 8,000 »*, non catégorisée *« Greater than 1,500 »*.
- **Strava** ([Climb Categorization](https://support.strava.com/hc/en-us/articles/216917057-Climb-Categorization)) : *« multiplying a segment's length in meters by its grade »* ; une montée si le produit *« is greater than 8,000 »* ; mêmes seuils 8 000 / 16 000 / 32 000 / 64 000 / 80 000.

Exemples (calcul) : 500 m à 7 % = 3 500 (non catégorisée) ; 2 km à 5 % = 10 000 (Cat. 4) ; 18 km à 7 % = 126 000 (HC, un grand col alpin).

Ces critères sont des règles publiques, pas une base de données : les reprendre ne copie rien.

### 4.2 Outils ouverts

- **`navigo`** (crate Rust, licence **MIT** d'après [crates.io](https://crates.io/crates/navigo), dépôt `totorototo/navigo`) : [`src/climbs.rs`](https://docs.rs/crate/navigo/0.1.0/source/src/climbs.rs) reprend la règle Garmin, `MIN_CLIMB_SCORE: f64 = 3.5; // km × %`, `MIN_CLIMB_DIST_KM: f64 = 0.5`, `MIN_AVG_GRADIENT: f64 = 3.0`, et dérive les montées de paires creux→sommet (*« For each peak, the nearest preceding valley is found »*, *« Each valley can only be claimed by one climb »*). Elle travaille sur **une trace**, pas sur un réseau routier, et reçoit les creux et sommets déjà détectés.
- **`droidgren/elevation_finder`** : outil web qui cherche les tronçons les plus raides sur des tuiles d'altitude ; pas de licence déclarée sur GitHub, donc non réutilisable.
- Aucun outil ouvert trouvé qui produise, à partir d'OSM et d'un MNT, des **montées nommées** prêtes à l'emploi. La logique creux→sommet + seuils tient en quelques centaines de lignes ; le travail est dans la préparation du réseau (§6).

---

## 5. Volumes réalistes

### 5.1 Repères

- **Climbfinder** (seulement pour l'ordre de grandeur, [page Europe](https://climbfinder.com/en/regions/europe)) : *« In Europe cyclists can find 90808 interesting climbs »*, *« Climbs have an average length of 3.5 km and 185 m of total ascent »* ; France 20 458, Italie 9 756, Espagne 7 373, Belgique 8 790, Suisse 2 428. Ce sont des montées choisies une à une par un site spécialisé, pas toutes les montées qui passent un seuil.
- **Cols OSM** : 4 166 en France, 40 045 nœuds dans le monde, dont plus d'un quart de cols d'alpinisme.

### 5.2 Estimation pour Nervo (calcul, à confirmer par un pilote)

Un col routier donne en général **deux ou trois montées** (une par versant et par route d'accès). Les montées sans col (vers un village, un plateau, un sommet) sont plus nombreuses que les cols. Avec le seuil Cat. 4 (score > 8 000, 500 m, 3 %) appliqué aux routes ouvertes aux vélos :

| Zone | Ride (estimation) |
|---|---:|
| France | 10 000 – 30 000 |
| Europe | ~10⁵ |
| Monde | 3·10⁵ – 10⁶ |

La fourchette basse correspond à une sélection « montées connues » (≈ Climbfinder) ; la haute à toutes les montées Cat. 4 détectées.

Pour la randonnée, la borne haute est le nombre de sommets : `natural=peak` compte **26 077** nœuds en France, **9 273** en Suisse, 1 113 753 dans le monde ([taginfo Geofabrik](https://taginfo.geofabrik.de/europe:france/tags/natural=peak)) ; seule une partie a un nom et un chemin d'accès qui passe le seuil (§8). Pour la course, aucun repère ouvert : le nombre dépend entièrement du seuil et du plafond par zone. Le **pilote sur un pays** (France ou Suisse) donnera le vrai ratio montées/cols, les volumes par sport et le bon seuil.

### 5.3 Critères de sélection proposés

- **Vélo** : routes `highway` de `trunk` à `residential` + `service`/`track` revêtus (`surface` dur), sans `bicycle=no` ; longueur ≥ 500 m, pente moyenne ≥ 3 %, score > 8 000 ; pente moyenne ≤ 20 % (au-delà : artefact du MNS). Popularité : bonus si la montée suit un `route=bicycle` ou finit à un `mountain_pass` nommé.
- **Dédoublonnage** : deux montées qui se recouvrent à plus de 80 % (distance de Hausdorff ou de Fréchet sous ~30 m) → garder la plus longue ; garder aussi une sous-montée si elle a son propre nom (col intermédiaire).
- **Nommage automatique** : (1) `name` du `mountain_pass` d'arrivée + « depuis <lieu de départ> », le lieu étant le `place=village|town|hamlet` OSM le plus proche du départ (« Col du Galibier depuis Valloire ») ; (2) sinon `name` ou `ref` de la route + lieu d'arrivée (« Montée de la D 902 vers Saint-Véran ») ; (3) sinon « Montée de <lieu> ». Les noms viennent d'OSM : ils font partie de la base dérivée.

---

## 6. Chaîne de production

### 6.1 Entrées

| Donnée | Taille mesurée (en-tête HTTP, 2026-11-05) |
|---|---:|
| [Planète OSM](https://planet.openstreetmap.org/pbf/) `planet-261026.osm.pbf` | 95,6 Go |
| [Geofabrik](https://download.geofabrik.de/) Europe | 35,4 Go |
| Geofabrik France | 5,1 Go |
| Geofabrik Suisse | 0,55 Go |
| Copernicus GLO-30 | 26 450 tuiles COG, ~40 Mo pour une tuile terrestre |

Les COG se lisent par plages HTTP : pas besoin de télécharger le jeu entier, seulement les tuiles traversées par les routes candidates.

### 6.2 Étapes

1. **Extraire** routes, chemins, cols, sommets et lieux (`osmium tags-filter`) d'un extrait Geofabrik, puis charger dans une base PostGIS **de travail** (pas la prod), par exemple avec `osm2pgsql`.
2. **Construire les chaînes** : fusionner les ways contiguës de même nom ou `ref` (`ST_LineMerge`), couper aux carrefours importants.
3. **Échantillonner** tous les ~25 m (`ST_Segmentize` puis `ST_DumpPoints`), lire l'altitude dans le MNT (GDAL/rasterio, ou `postgis_raster` `ST_Value`), lisser, seuil d'hystérésis de 2 m (#14).
4. **Détecter** les paires creux→sommet dans les deux sens de chaque chaîne, appliquer les seuils (§4.1, §5.3). Amorcer en priorité depuis chaque `mountain_pass` situé sur une route.
5. **Dédoublonner**, **nommer**, **simplifier** (`ST_Simplify` ~5 m), calculer `distance_m`, `avg_grade`, D+.
6. **Exporter** en GeoPackage/GeoJSON sous ODbL (le fichier à offrir, §2.3) avec les mentions OpenStreetMap et Copernicus.
7. **Charger** en prod de façon **idempotente** : une clé source stable (par exemple un hachage des identifiants de ways OSM et des extrémités arrondies) pour qu'une relance n'insère pas de doublon.
8. **Rétro-appariement** : chaque nouveau Segment déclenche la recherche des Activities passées qui le couvrent (décidé à la carte). L'index GiST sur `activity_track.route` existe déjà (ADR-017).

### 6.3 Où et quand

- **Pas sur le VPS** pour l'Europe ou le monde (96 Go de PBF, MNT, base de travail). Un **script ponctuel** (`scripts/segments-nervo/`) lancé sur un poste ou une machine louée à l'heure, pays par pays ; la prod ne reçoit que le résultat.
- **Relance** : annuelle ou à la demande, par pays. Une relance **ajoute** les nouvelles montées et **ne modifie jamais** un Segment existant (modifier un tracé est hors carte). Une route disparue d'OSM laisse son Segment en place ; l'Administrateur peut le supprimer.
- **Ordre** : pilote sur la France ou la Suisse, mesure des volumes et revue manuelle d'un échantillon, puis Europe, puis le reste du monde.

---

## 7. Coût en base et effet sur l'appariement

### 7.1 Stockage (calcul)

Montée moyenne de 3,5 km simplifiée à un point tous les ~25 m : ~140 points × 16 octets (2D) ≈ **2,2 Ko**, ~3,4 Ko avec l'altitude (Z). Avec `start_point`, `end_point` et les autres colonnes, compter **2,5 à 3,5 Ko par ligne** :

| Segments Nervo | Table | GiST `path` + `start_point` |
|---:|---:|---:|
| 30 000 (France) | ~0,1 Go | ~3 Mo |
| 100 000 | ~0,3 Go | ~10 Mo |
| 1 000 000 | ~3 Go | ~100 Mo |

Une entrée GiST stocke une boîte englobante (16 octets en 2D) plus l'en-tête du tuple, soit ~40–50 octets. Ces chiffres sont des calculs, pas des mesures.

### 7.2 Candidats par Activity

PostGIS ([Using Spatial Indexes](https://postgis.net/docs/using_postgis_query.html)) : `ST_DWithin` utilise *« the && operator internally on an expanded bounding box of the query geometry »* ; *« The spatial index allows retrieving only records with geometries whose bounding boxes overlap the expanded extent »* ; *« The actual distance is then computed to confirm whether to include the record in the result set. »* Le filtre de l'index dépend donc de la **boîte englobante du tracé de l'Activity**.

Calcul : la densité française de montées connues est de 20 458 / ~550 000 km² (superficie approchée de la France métropolitaine) ≈ **0,037 par km²** (une pour 27 km²), 5 à 10 fois plus en montagne. Une sortie vélo de 60 km en boucle a une boîte d'environ 20 × 15 km = 300 km² : **~11 départs de Segments** dans la boîte en moyenne, **50 à 100** dans les Alpes. Le test exact (départ à quelques dizaines de mètres du tracé) n'en garde qu'une poignée, puis la vérification de bout en bout d'ADR-019 §8 s'applique à ceux-là seulement. Le filtre par sport réduit encore (une sortie vélo ne voit pas les Segments de course).

[`ST_Subdivide`](https://postgis.net/docs/ST_Subdivide.html) : *« Since the bounding boxes for the parts usually cover a smaller area than the original geometry bbox, index queries produce fewer "hit" cases. »* Découper le tracé de l'Activity en morceaux avant la recherche transforme la grande boîte en un couloir. C'est utile pour les longues sorties en boucle.

Conclusion : quelques dizaines de candidats au pire, chacun vérifié en millisecondes. Les Segments Nervo ne changent pas l'ordre de grandeur du coût de `match-segments`. La charge à surveiller est le **rétro-appariement** au chargement initial d'un pays (beaucoup de Segments d'un coup), à lancer en tâche de fond par lots.

---

## 8. Course, marche, randonnée

- **Ce qu'OSM ne donne pas** : pas de « montées de course » ni de « boucles de parc » prêtes ; `route=running` (1 368 relations dans le monde) et `route=fitness_trail` (991) sont marginaux. Les Segments de course de Strava viennent de la foule (côtes de quartier, quais, ponts), pas d'une base ouverte.
- **Randonnée** : la montée vers un **sommet nommé** est l'équivalent du col. Départ : col, parking ou fin de route ; arrivée : `natural=peak` avec `name` (697 354 dans le monde) et si possible `ele` ; chemins `highway=path|track|footway` avec `sac_scale` ≤ `demanding_mountain_hiking` (au-delà, on sort de la randonnée vers l'alpinisme). Seuil proposé : D+ ≥ 200–300 m. Attention au biais du MNS en forêt (§3.3) : caler les extrémités sur `ele`.
- **Course** : peu de Segments, ciblés : montées courtes en ville et en périphérie (score ≥ 1 500, longueur ≥ 500 m, pente ≥ 3 % : seuil « non catégorisé » de Garmin) sur rues et chemins accessibles à pied (`foot` différent de `no`, pas d'autoroute ni de voie rapide), plafonnées par zone ; plus les montées vélo accessibles à pied. Le reste viendra des athlètes.
- **Marche** : **aucun Segment Nervo**. L'intérêt d'un classement de marche est faible et les athlètes peuvent en créer.
- **Un tracé, plusieurs sports** : le schéma a un seul `sport_type_code` par Segment. Proposer la même montée en `ride` et en `run` crée deux lignes, deux classements, deux index. Alternative : un Segment multi-sport avec un classement par sport. À trancher à la carte (modèle de données).

---

## 9. Recommandation

1. **Source** : OpenStreetMap (tracés, noms, cols, sommets) + **Copernicus GLO-30** (altitude), SRTM en secours, MNT national si disponible. Pas de FABDEM ni d'Open-Meteo.
2. **Licence** : assumer l'ODbL. Créditer OpenStreetMap (et Copernicus) dans l'app ; publier gratuitement le fichier des Segments créés par Nervo sous ODbL ; accepter que tous les Segments, athlètes compris, soient offerts sous ODbL sans créateur ; Efforts et traces restent privés de toute obligation.
3. **Production** : générateur hors ligne par pays, export ODbL, chargement idempotent, rétro-appariement en tâche de fond, relances qui ajoutent sans modifier.
4. **Périmètre par sport** : vélo (montées Cat. 4+), randonnée (montées vers un sommet nommé), course (quelques montées courtes et les montées vélo praticables à pied), marche (rien).
5. **À décider à la carte #223** : colonnes de provenance (`created_by` nul ou « Nervo », clé source), Segment mono- ou multi-sport, emplacement de la mention OSM dans l'app, URL du fichier ODbL, pilote France ou Suisse.

---

## Annexe : requêtes utilisées

- Taginfo planète : `https://taginfo.openstreetmap.org/api/4/tag/stats?key=mountain_pass&value=yes` (idem pour les autres tags), `.../key/stats?key=incline`, `.../key/values?key=incline`, `.../tag/combinations?key=mountain_pass&value=yes`.
- Taginfo par pays : `https://taginfo.geofabrik.de/europe:france/api/4/tag/stats?...` (France, Suisse, Belgique, Italie, Espagne).
- GeoNames : `https://download.geonames.org/export/dump/FR.zip` et `CH.zip`, comptage des lignes de code de classe `PASS`.
- Overpass (Suisse) : `[out:json];area["ISO3166-1"="CH"][admin_level=2]->.a;way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|living_street|road)$"](area.a)->.w;node(w.w)["mountain_pass"="yes"];out count;`, puis la même avec `track|path|footway|bridleway|cycleway|steps`.
- Tailles : en-têtes `Content-Length` des fichiers Geofabrik et planète ; `https://copernicus-dem-30m.s3.amazonaws.com/tileList.txt` pour le nombre de tuiles.
