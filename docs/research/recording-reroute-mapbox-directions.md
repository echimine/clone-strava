# Recherche : recalcul de chemin pendant une Recording avec Mapbox Directions

- **Ticket** : [Recalcul de chemin pendant une Recording avec Mapbox Directions : conditions, quotas, coût](https://github.com/echimine/clone-strava/issues/57) (carte [Enregistrer une Activity en direct sur iOS](https://github.com/echimine/clone-strava/issues/43))
- **Date** : 2026-10-12
- **Contexte** : une **Recording** (« Enregistrement ») est la capture en cours d'une Activity ; un **Itinerary** (« Itinéraire ») est un chemin planifié à la main avant de sortir (`CONTEXT.md`). [Distance restante sur l'Itinéraire pendant une Recording](https://github.com/echimine/clone-strava/issues/49) a fixé le mode hors ligne (progression le long du tracé en cache, valeur figée « Hors Itinéraire » quand on quitte le tracé) et ajouté au périmètre un recalcul de chemin en ligne, affiché sans instructions. ADR-030 appelle déjà Mapbox Directions en REST depuis l'app (`MapboxDirectionsRouter`, jeton `MAPBOX_ITINERARIES_TOKEN`) et a relevé §2.10.1 et §2.9.1 des Product Terms.
- **Question** : peut-on appeler Mapbox Directions (REST, sans SDK) pendant une Recording pour recalculer un chemin depuis la position de l'athlète, à quelles conditions, pour quel coût, avec quels paramètres, et que font Strava, Komoot et Garmin ?
- **Sources** : Mapbox Product Terms du 21 juillet 2026 (PDF lié depuis [mapbox.com/legal/product-terms](https://www.mapbox.com/legal/product-terms)), [doc Directions API](https://docs.mapbox.com/api/navigation/directions/), [guide des API Mapbox (limites)](https://docs.mapbox.com/api/guides/), [page de prix Mapbox](https://www.mapbox.com/pricing), [guide de prix du Navigation SDK iOS](https://docs.mapbox.com/ios/navigation/guides/pricing/), [guide Rerouting du Navigation SDK iOS](https://docs.mapbox.com/ios/navigation/guides/turn-by-turn-navigation/rerouting.md), documentation Apple `CLLocation`, centre d'aide et annonces Strava, centre d'aide komoot (lu via l'API Zendesk publique du centre d'aide, le site bloquant les robots), manuel Garmin Edge 1050, code du repo à `b35c7a2`. Tout a été lu le **2026-10-12**. Les citations sont verbatim, en anglais.

> Ce document établit des faits. Il ne tranche pas : les choix sont listés au §6 et renvoyés à [Recalcul du chemin quand l'athlète quitte l'Itinéraire](https://github.com/echimine/clone-strava/issues/58).

> **Note (2026-10-12, décision postérieure à la recherche)** : l'app ne sera jamais publiée, donc l'interdiction de stocker les résultats Directions (§2.10.1, §1.9 (v)) est **écartée**, comme ADR-030 l'a fait pour les Itinéraires. Le chemin recalculé et sa distance peuvent être enregistrés en base (GRDB, état persisté de la Recording) et réutilisés à la reprise sans nouvelle requête. Le risque reste celui d'ADR-030 : Mapbox peut révoquer le jeton, et il faut corriger avant toute publication. Les autres conditions, dont l'absence de sondage périodique (§1.9 (i) et (ii)), restent valables. Le reste du document décrit les conditions telles qu'elles sont écrites. Voir [la décision sur #58](https://github.com/echimine/clone-strava/issues/58#issuecomment-6131093588).

---

## TL;DR

1. **Les Product Terms n'interdisent pas un recalcul affiché sans être stocké.** Aucune clause ne réserve le recalcul en temps réel au Navigation SDK, et la doc Directions présente elle-même `bearings` comme utile *« for making sure the new routes of rerouted vehicles continue traveling in their current direction »*. Trois conditions restent à respecter :
   - **ne rien garder** du résultat (§2.10.1 : pas d'*« export, download, cache or store »*). Le chemin recalculé et sa distance ne vont ni dans GRDB, ni dans l'état persisté de la Recording, ni dans la trace ;
   - **déclencher sur un événement de l'athlète**, pas en sondage périodique (§1.9 (i) et (ii) : *« only query the Services in response to human user queries and human application interactions »*, *« not perform bulk or automated queries »*). Un recalcul sur un bouton est clairement couvert. Un recalcul automatique quand l'athlète quitte le tracé est défendable, puisque le Navigation SDK de Mapbox fait exactement cela par défaut, mais la clause ne le dit pas ;
   - **§2.9.1** (*« Mobile SDKs as Customer's exclusive means of accessing the Service Offerings in mobile applications »*) reste ambigu pour un appel REST depuis l'app. C'est la même ambiguïté qu'ADR-030 a déjà acceptée : le recalcul n'ajoute pas d'écart nouveau, contrairement au stockage des Itinéraires (ADR-030 §1).
2. **Quotas et coût** : 300 requêtes/min **par jeton** (HTTP 429 au-delà), 25 coordonnées par requête, facturée comme une seule requête. Gratuit jusqu'à **100 000 requêtes/mois**, puis 2,00 $ / 1,60 $ / 1,20 $ les 1 000 par palier. Un recalcul par sortie du tracé coûte de 0 à ~6 requêtes par sortie (≈ 0,01 $ au-delà du gratuit) ; un recalcul périodique toutes les 30 s hors du tracé en coûte des dizaines à des centaines. Le Navigation SDK facture au trajet (0,08 $ au-delà de 1 000 trajets/mois), bien plus cher.
3. **Profils et paramètres** : `walking` pour `run`, `walk`, `hike` et `cycling` pour `ride` (déjà dans `ItinerarySport.routingProfile`). Utiles : `bearings` sur le premier point (cap GPS ± 45° ou 90°), `radiuses` (rayon d'accroche, `unlimited` possible, sinon `NoSegment`), `overview=full` + `geometries=polyline6`, `steps=false` (pas d'instructions). `approaches` n'accepte que `unrestricted`/`curb` (côté de la route) et n'apporte rien à pied ou à vélo. `avoid_maneuver_radius` est réservé aux profils voiture.
4. **Destination** : viser l'**arrivée** court-circuite le reste de l'Itinéraire, et sur une boucle (départ = arrivée) ramène directement au départ. Viser un **point de retour sur le tracé**, en avant de la progression, est ce que font komoot et Garmin ; la distance restante devient alors distance du chemin recalculé + distance restante du tracé depuis ce point.
5. **Concurrents** :
   - **Strava** ne documente **aucun recalcul** : seulement une alerte « Off-Route » (abonnés), qui disparaît au retour sur le tracé.
   - **komoot** recalcule **automatiquement**, **vers le point le plus proche du tracé** et non vers l'arrivée, **uniquement en ligne**. Hors ligne, il garde le tracé d'origine et signale la sortie.
   - **Garmin Edge 1050** propose à la sortie du tracé « Pause Navigation » ou « Re-route ». La première suggestion de Re-route est *« the shortest route back to the course »* et démarre seule après 10 s. Le calcul se fait sur l'appareil avec des cartes téléchargées.

---

## 1. Conditions d'utilisation (Mapbox Product Terms, 21 juillet 2026)

Source : PDF *Mapbox Product Terms (July 21, 2026)*, lié depuis [mapbox.com/legal/product-terms](https://www.mapbox.com/legal/product-terms). C'est la version déjà lue pour [Routage et dénivelé Mapbox pour les Itinéraires](https://github.com/echimine/clone-strava/issues/6) ; elle n'a pas changé depuis.

### 1.1 Les clauses qui s'appliquent

> **2.10.1. Navigation APIs.** Customer shall not export, download, cache or store results from any request to a Navigation API.

> **3.51** "Navigation APIs" means Mapbox's navigation service APIs as described in Mapbox documentation. Navigation APIs may be accessed directly or through a Navigation SDK.

Directions est listée sous *Navigation APIs* dans l'[index de la doc Mapbox](https://docs.mapbox.com/llms.txt) (avec Map Matching, Isochrone, Optimization, Matrix).

> **1.9 Default Restrictions.** Except as otherwise expressly permitted under these Product Terms, Customer shall (i) only query the Services in response to human user queries and human application interactions, (ii) not perform bulk or automated queries, (iii) not scrape or systematically download Licensed Map Content, (iv) only access Licensed Map Content (other than Data Products) directly from Mapbox APIs, and (v) not export, download, cache or store Licensed Map Content or other results from the Service Offerings.

> **1.6 No Tracing, Deriving, or Extracting.** Customer shall not trace or otherwise derive or extract content, data and/or information from the Service Offerings […]

> **2.9.1. Mobile SDKs.** In addition to compliance with the Mapbox SDK terms below, Customer shall use the Mobile SDKs as Customer's exclusive means of accessing the Service Offerings in mobile applications. […]

> **3.49** "Mobile SDKs" means the Mapbox SDKs for mobile applications, including the Maps SDK and Navigation SDK for Mobile.

> **3.1** "Active Guidance Session" means a navigation session that has turn-by-turn directions to a specific destination. […] **3.29** "Free-Drive Session" means a navigation session without a specific destination. […] **3.78** "Trip" means either an Active Guidance Session or a Free-Drive Session. A Trip includes all API requests for navigation resources by the Navigation SDK to support the session.

### 1.2 Ce qu'elles disent pour un recalcul pendant une Recording

| Point | Clause | Lecture |
|---|---|---|
| Recalcul en temps réel hors Navigation SDK | aucune | **Rien ne le réserve au SDK.** Les notions de session et de trajet (§3.1, §3.29, §3.78) ne servent qu'à la facturation du SDK. La doc Directions décrit l'usage : `bearings` *« is useful for making sure the new routes of rerouted vehicles continue traveling in their current direction »* ; elle mentionne aussi *« real-time routing »* à propos de `depart_at=now`. |
| Afficher le chemin et sa distance | §2.10.1, §1.9 (v) | Afficher n'est ni exporter, ni télécharger, ni stocker. **Permis tant que le résultat ne vit qu'en mémoire, le temps de l'affichage.** |
| Garder le chemin recalculé (GRDB, état persisté de la Recording pour [Persistance et reprise d'une Recording](https://github.com/echimine/clone-strava/issues/52), trace envoyée au serveur, Activity) | §2.10.1, §1.9 (v) | **Interdit.** À la reprise, il faut redemander un chemin. La progression le long du tracé ([Distance restante sur l'Itinéraire pendant une Recording](https://github.com/echimine/clone-strava/issues/49)) n'est pas un résultat de Directions recalculé : sa persistance relève de l'écart déjà accepté par ADR-030 pour le tracé en cache. |
| Distance restante = distance Mapbox + reste du tracé | §1.6 | `routes[0].distance` est un champ de la réponse : l'afficher n'est pas en dériver un jeu de données. L'additionner au reste du tracé pour l'affichage reste un usage d'affichage. **Ne pas la mémoriser** (même règle que ci-dessus). |
| Déclenchement | §1.9 (i), (ii) | **Bouton « Recalculer »** : *« human user query »*, couvert sans ambiguïté. **Recalcul automatique à la sortie du tracé** : déclenché par le déplacement de l'athlète, défendable comme *« human application interaction »*, et c'est le comportement par défaut du Navigation SDK de Mapbox (§4.1). **Sondage périodique** (toutes les N s tant qu'on est hors du tracé) : ce qui ressemble le plus à des *« automated queries »*. |
| Appel REST depuis l'app iOS | §2.9.1 | Ambigu, comme noté par ADR-030 §2 : le Maps SDK n'offre pas Directions, et l'accès conforme à la lettre passerait par le Navigation SDK (module `MapboxDirections` de la v3, incompatible avec notre MapboxMaps selon ADR-030). Le recalcul n'aggrave pas la situation déjà acceptée. |
| Attribution | §1.4.1 | Logo Mapbox, « © Mapbox », « © OpenStreetMap » : déjà rendus par la carte du Maps SDK. Si un chemin recalculé est affiché hors de la carte (Live Activity sans carte, par exemple), seule sa distance l'est ; aucune clause ne demande d'attribution pour un nombre seul, mais la doc ne le dit pas explicitement. |

**Verdict** : les conditions **n'interdisent pas** l'usage. Elles l'encadrent : résultat jamais stocké, requêtes déclenchées par l'athlète ou par sa sortie du tracé (pas de sondage), et ambiguïté §2.9.1 inchangée par rapport à ADR-030.

### 1.3 Clauses générales, sans lien propre au recalcul

- §1.3.4 interdit *« operating a product or service where the use or failure of the Service Offerings could reasonably be expected to lead to death, personal injury, or property or environmental damage »*. La clause vise toute l'app (carte, Itinéraires), pas le recalcul en particulier ; Mapbox vend par ailleurs du guidage. Elle pousse seulement à présenter le chemin recalculé comme indicatif.
- §1.2.2 exige une licence supplémentaire pour les applications *« primarily intended for use within vehicles »*. Une app de sport n'est pas dans ce cas ; rien de nouveau avec le recalcul.

---

## 2. Quotas et coût

### 2.1 Limites

- *« Maximum 300 requests per minute. Requests that contain multiple coordinates are counted as 1 request. »* ([Directions API](https://docs.mapbox.com/api/navigation/directions/))
- *« Note that all rate limits are counted per access token, not per account. »* ; au-delà, *« your request will be throttled and you will receive a HTTP 429 Too Many Requests response »*. En-têtes `X-Rate-Limit-Interval` (toujours 60), `X-Rate-Limit-Limit`, `X-Rate-Limit-Reset` ([API guides](https://docs.mapbox.com/api/guides/)). `MapboxDirectionsRouter` gère déjà le 429 (`RoutingError.rateLimited`).
- Distance totale maximale entre les points : *« 1,500 kilometers for the cycling profile. 1,000 kilometers for the walking profile. »*
- *« a size limit of approximately 8100 bytes on GET request URLs »* ; `POST` possible au-delà. Avec 2 coordonnées, sans objet.

### 2.2 Prix

[Page de prix Mapbox](https://www.mapbox.com/pricing), section Navigation, par 1 000 requêtes et par mois :

| Requêtes Directions / mois | Prix pour 1 000 |
|---|---|
| 0 – 100 000 | gratuit |
| 100 001 – 500 000 | 2,00 $ |
| 500 001 – 1 000 000 | 1,60 $ |
| 1 000 001 – 5 000 000 | 1,20 $ |
| au-delà | sur devis |

*« A request that contains multiple waypoints is billed as a single API request. »* Le palier gratuit est un volume de compte (la page parle de requêtes mensuelles, pas de jetons) : **il est partagé avec l'éditeur d'Itinéraires** (ADR-030), même si le recalcul utilise un autre jeton. C'est une lecture de la page de prix, Mapbox ne le formule pas en ces termes.

Pour comparaison, le **Navigation SDK v3** en « metered trips » : 100 MAU gratuits puis 0,30 $ par MAU ; 1 000 trajets gratuits puis 0,08 $ / 0,064 $ / 0,048 $ par trajet. Les requêtes Directions faites pendant une session du SDK sont incluses : *« you will not be billed separately for any requests made during the navigation session »* ([guide de prix](https://docs.mapbox.com/ios/navigation/guides/pricing/)). Un trajet à 0,08 $ coûte autant que 40 requêtes REST à 2 $ les 1 000.

### 2.3 Estimation par sortie

Hypothèses de déclenchement (à trancher dans [Recalcul du chemin quand l'athlète quitte l'Itinéraire](https://github.com/echimine/clone-strava/issues/58)) :

- **H1, un recalcul par sortie du tracé** : une requête quand l'athlète est hors du tracé depuis un certain temps (seuil de 50 m comme l'accroche, plus un délai), puis une nouvelle seulement s'il quitte aussi le chemin recalculé, avec un intervalle minimal (30 s par exemple). Une sortie typique compte 0 à 3 écarts → **0 à ~6 requêtes**.
- **H2, recalcul périodique hors du tracé** : une requête toutes les 30 s tant que l'athlète est hors du tracé. Un détour de 10 min = 20 requêtes ; 3 détours ≈ **60 requêtes**.
- **H3, pire cas sans plafond** : l'athlète ignore l'Itinéraire pendant 2 h avec H2 → **240 requêtes** (720 avec un intervalle de 10 s).

| Sorties avec Itinéraire / mois | H1 (~3 req.) | H2 (~60 req.) | H3 (~240 req.) |
|---|---|---|---|
| 1 000 | 3 000 → gratuit | 60 000 → gratuit | 240 000 → 280 $ |
| 10 000 | 30 000 → gratuit | 600 000 → 960 $ | 2,4 M → 3 280 $ |

(Calcul : 400 000 × 2,00 $ + 500 000 × 1,60 $ + le reste × 1,20 $, par 1 000, sans compter les requêtes de l'éditeur d'Itinéraires.)

**Débit** : avec H1, 300 req/min ne sont jamais approchées. Avec H2 (2 req/min par athlète hors tracé), **150 athlètes hors tracé en même temps** saturent un jeton, et l'éditeur d'Itinéraires en pâtit s'il partage le même jeton.

---

## 3. Requête Directions pour un recalcul

### 3.1 Profils

- *« mapbox/walking — For pedestrian and hiking routing. This profile shows the optimal path by using sidewalks and trails. »*
- *« mapbox/cycling — For bicycle routing. This profile shows routes that are short and safer for cyclists by avoiding highways and preferring streets with bike lanes. »*
- Pas de profil trail, VTT ou gravel. Le code fait déjà la correspondance : `ItinerarySport` `run`, `walk`, `hike` → catégorie `foot` → `walking` ; `ride` → `wheels` → `cycling` (`apps/mobile/StravaClone/Features/Itineraries/Domain/ItinerarySport.swift`). L'Itinéraire suivi porte le même sport que la Recording au départ ([Parcours de démarrage d'une Recording](https://github.com/echimine/clone-strava/issues/48)), mais le sport peut être modifié avant le départ : le profil doit venir du **sport de la Recording**.
- `walking_speed` (0,14 à 6,94 m/s, défaut 1,42) ne change que la durée estimée ; `walkway_bias` (−1 à 1) favorise ou évite les trottoirs et chemins piétons.

### 3.2 Paramètres utiles

Forme : `GET /directions/v5/mapbox/{walking|cycling}/{lon,lat};{lon,lat}?…` (2 coordonnées : position, puis destination).

| Paramètre | Doc (extraits) | Usage pour un recalcul |
|---|---|---|
| `coordinates` | *« between two and 25 {longitude},{latitude} coordinate pairs to visit in order »* | Position actuelle, puis point de destination (§3.3). |
| `bearings` | *« Influences the direction in which a route starts from a waypoint. […] useful for making sure the new routes of rerouted vehicles continue traveling in their current direction. A request that does this would provide bearing and radius values for the first waypoint and leave the remaining values empty. Takes two comma-separated values per waypoint: an angle clockwise from true north between 0 and 360, and the range of degrees by which the angle can deviate (recommended value is 45° or 90°) »* ; même longueur que `coordinates`, valeur sautée avec `;` | Premier point : `LocationSample.course` (déjà présent dans le modèle), par exemple `{course},45;`. Apple : *« A negative value indicates that the course information is invalid. »* `courseAccuracy` donne la marge en degrés ; `LocationSample` ne la porte pas aujourd'hui. Sans cap valide (à l'arrêt, en Pause), ne pas envoyer `bearings`. À pied, faire demi-tour est naturel : un cap imposé peut créer un détour. |
| `radiuses` | *« The maximum distance a coordinate can be moved to snap to the road network, in meters. […] Values can be any number greater than 0 or the string unlimited. A NoSegment error is returned if no routable road is located within the radius. »* | Premier point : un randonneur hors sentier peut être loin du réseau ; un rayon serré renvoie `NoSegment`, `unlimited` accroche n'importe où. Point de retour : le tracé en cache peut contenir des tronçons `straight` hors réseau (ADR-030 §2), et le cache ne garde pas les Legs (ADR-030 §8), donc on ne sait pas si le point choisi est sur le réseau. L'éditeur utilise 200 m (`MapboxDirectionsRouter.snapRadiusMeters`). |
| `approaches` | *« Accepts unrestricted (default […]) or curb (route will arrive at the waypoint on the driving_side of the region) »* | Sans intérêt à pied ou à vélo : laisser le défaut. |
| `continue_straight` | *« Defaults to […] false for mapbox/walking and mapbox/cycling »* | Ne concerne que les points intermédiaires ; défaut suffisant. |
| `geometries`, `overview` | `polyline6` (*« precision of six decimal places »*) ; `full` (*« the most detailed geometry available »*) | Comme l'éditeur. |
| `steps` | *« Whether to return steps and turn-by-turn instructions (true) or not (false, default). »* | `false` : aucune instruction (guidage hors périmètre de la carte). |
| `alternatives` | *« Up to two alternatives may be returned »*, disponible pour `walking` et `cycling` | Non nécessaire. |
| `waypoints` | indices des coordonnées qui délimitent les étapes ; *« Must be used in conjunction with steps=true »* | Inutilisable sans `steps=true`. |
| `avoid_maneuver_radius` | disponible pour *« mapbox/driving-traffic and mapbox/driving »* | Non disponible à pied ou à vélo. |

Réponse : `routes[0].distance` (*« The distance traveled through the waypoints, in meters »*), `duration`, `geometry`. Codes sous HTTP 200 : `NoRoute` (*« There was no route found »*) et `NoSegment` (*« No road segment could be matched for one or more coordinates within the supplied radiuses »*), que `MapboxDirectionsRouter` traite déjà comme `RoutingError.noPath`.

### 3.3 Destination : l'arrivée ou un point de retour sur le tracé

| Destination | Effet | Distance restante affichée |
|---|---|---|
| **Arrivée de l'Itinéraire** `[position, arrivée]` | Ignore tout le reste du tracé. Sur une **boucle** (départ = arrivée) ou un **aller-retour**, ramène directement au départ et abandonne le parcours prévu. Ajouter des points du tracé restant (jusqu'à 23 intermédiaires) le force à passer par eux, mais Mapbox choisit librement le chemin entre deux points, qui peut alors s'écarter de l'Itinéraire. | `routes[0].distance` |
| **Point de retour sur le tracé** `[position, point P]`, P en avant de la progression | Rejoint l'Itinéraire puis le suit (tracé en cache). C'est le comportement documenté de komoot et la première suggestion de Garmin (§4). Choix de P : point du tracé le plus proche en avant (fenêtre de [Distance restante sur l'Itinéraire pendant une Recording](https://github.com/echimine/clone-strava/issues/49)), ou point plus loin pour ne pas revenir en arrière. | `routes[0].distance` + (distance totale − progression en P) |

Pour comparer plusieurs points P en une requête, l'API **Matrix** accepte 25 coordonnées, **60 requêtes/min** par jeton (et non 300) et facture *chaque paire origine-destination* au même tarif que Directions ([API guides](https://docs.mapbox.com/api/guides/), [page de prix](https://www.mapbox.com/pricing)). C'est aussi une Navigation API (§2.10.1).

---

## 4. Ce que font Strava, komoot et Garmin

### 4.1 Le Navigation SDK de Mapbox, pour référence

[Rerouting (Navigation SDK iOS v3)](https://docs.mapbox.com/ios/navigation/guides/turn-by-turn-navigation/rerouting.md) : *« By default, if a user is off-route, a new route is generated from their current location to the next waypoint. »* On peut le couper (`rerouteConfig.detectsReroute = false`). Le SDK vérifie aussi *« for a faster route every two minutes by making a request to the Direction API »*. Mapbox considère donc le recalcul automatique à la sortie du tracé comme l'usage normal d'une session de navigation.

### 4.2 Strava

- [Recording an Activity, « Off-Route Alerts »](https://support.strava.com/en-us/articles/15402137-recording-an-activity) : *« When you record with a saved route loaded, Strava tracks your position relative to the route. If you move a meaningful distance away, an alert appears on your recording screen — on Apple Watch, the Mobile Record screen, or the iOS Live Activity widget (Lock Screen and Dynamic Island). The alert dismisses automatically once you return to the route. Minor GPS drift won't trigger it. »* Activées par défaut, désactivables dans les réglages de navigation.
- [Communiqué du 11 juin 2026](https://press.strava.com/articles/strava-adds-new-features-for-hiking-making-the-outdoor-experience-more-discoverable-navigable-and-social) : *« Off-Route Alerts - notifies athletes when they stray from a planned route, so they can course-correct before getting lost (subscribers only) »* ; *« Offline Routes - download routes for use in low- or no-connectivity areas […] (subscribers only) »*.
- **Aucun recalcul de chemin** n'est documenté dans l'aide ni dans les annonces lues : l'athlète est seulement averti et revient seul sur le tracé. ([How Do I Follow a Route on Strava?](https://support.strava.com/en-us/articles/15401749-how-do-i-follow-a-route-on-strava) ne parle pas de sortie du tracé.)

### 4.3 komoot

- [Navigation FAQ](https://support.komoot.com/hc/en-us/articles/10605424981402-Navigation-FAQ) (modifiée le 2026-05-15) :
  - *« When you deviate from the planned route, the route line changes color to indicate that you are off-route. […] Once you return to the planned route or automatic rerouting finds a new path, the route line returns to its normal color and guidance continues. »*
  - *« Automatic rerouting requires an internet connection. If you are navigating offline, komoot cannot calculate a new path. It will continue showing the original route and alert you that you are off-route, but no new route will be calculated until you reconnect. »*
  - *« Komoot's automatic rerouting is designed to get you back onto the planned route rather than recalculate an entirely new route to the destination. If you deviate, the most likely result is a path back to the nearest point on your original planned route, not a direct shortcut to the end. »* Pour aller ailleurs, il faut arrêter la navigation et éditer l'itinéraire dans le planificateur.
  - Limites : pas de recalcul en sortie de groupe ; *« If you deviate from a hiking trail, komoot may route you back to the nearest mapped path rather than finding a shortcut. »*
- [Download routes and maps for offline use](https://support.komoot.com/hc/en-us/articles/10356476920986-Download-routes-and-maps-for-offline-use) (modifiée le 2026-08-13) confirme : *« Auto-rerouting: Rerouting requires an internet connection. »*
- [App komoot pour Garmin](https://support.komoot.com/hc/en-us/articles/10317378384666-Use-the-komoot-app-for-Garmin) : *« Auto re-routing recalculates a path back to your planned route if you leave it (internet connection required). Your original komoot route is not permanently changed. »*

### 4.4 Garmin (Edge 1050)

- [Rerouting a Course](https://www8.garmin.com/manuals/webhelp/GUID-08ACA9FC-DEE6-4C8D-8A95-F62181C512E9/EN-US/GUID-62C3249E-F56E-467B-A9DA-83D907CDF4E6.html) : *« When you go off course, select an option: To pause navigation until you get back on course, select Pause Navigation. To choose from rerouting suggestions, select Re-route. NOTE: The first rerouting option is the shortest route back to the course and starts automatically after 10 seconds. »*
- [Route Settings](https://www8.garmin.com/manuals/webhelp/GUID-08ACA9FC-DEE6-4C8D-8A95-F62181C512E9/EN-US/GUID-75D72D8E-4D22-41E2-A11A-15250A9CC91D.html) : *« Course Recalculation: Automatically recalculates the route when you deviate from the course. »* [Course Settings](https://www8.garmin.com/manuals/webhelp/GUID-08ACA9FC-DEE6-4C8D-8A95-F62181C512E9/EN-US/GUID-5FB6AF7B-6157-4AFC-B82B-C3AEED568646.html) : *« Off Course Warnings: Alerts you if you stray from the course. »*
- Le manuel décrit des cartes téléchargées sur l'appareil (*« Managing Maps »*, `Map Manager`, Wi-Fi requis pour les mettre à jour) et n'indique aucun besoin de réseau pour recalculer. Le calcul se fait donc a priori sur l'appareil, hors ligne : c'est une déduction, le manuel ne le dit pas en ces termes.

### 4.5 Synthèse

| | Hors du tracé | Recalcul | Destination | Hors ligne |
|---|---|---|---|---|
| Strava | Alerte (abonnés), disparaît au retour | Aucun documenté | — | Alerte seulement |
| komoot (app) | Ligne noire + alerte | Automatique | Point le plus proche du tracé, pas l'arrivée | Pas de recalcul, alerte |
| Garmin Edge 1050 | Message, avertissements configurables | Au choix : pause ou suggestions ; la première part seule après 10 s | Plus court retour vers le tracé | Cartes sur l'appareil (déduit) |
| Navigation SDK Mapbox | État `offRoute` | Automatique par défaut, désactivable | Prochain point de passage | — |

---

## 5. Ce que cela change pour l'app

- Le recalcul s'ajoute au mode hors ligne fixé par [Distance restante sur l'Itinéraire pendant une Recording](https://github.com/echimine/clone-strava/issues/49) : sans réseau, ou en attendant la réponse, on garde la valeur figée et « Hors Itinéraire ». C'est le comportement de komoot hors ligne.
- Viser un point de retour en avant de la progression réutilise la recherche en avant de ce ticket ; une fois le tracé rejoint, la progression reprend normalement et le chemin recalculé est oublié.
- Rien du recalcul ne peut entrer dans l'état persisté pour [Persistance et reprise d'une Recording](https://github.com/echimine/clone-strava/issues/52) : à la reprise, si l'athlète est toujours hors du tracé, il faut redemander. *(Écarté par la décision notée en tête : le chemin recalculé peut être persisté.)*
- `MapboxDirectionsRouter` sait déjà construire la requête, décoder `polyline6` et classer les erreurs (`noPath`, `rateLimited`, `temporary`) ; il lui manque `bearings` et un rayon par point.

## 6. Décisions renvoyées à [Recalcul du chemin quand l'athlète quitte l'Itinéraire](https://github.com/echimine/clone-strava/issues/58)

Ce sont des choix, pas des faits :

- **Déclenchement** : automatique à la sortie du tracé (comme komoot et le SDK Mapbox), sur demande (bouton), ou les deux ; seuil de distance et délai avant de déclarer la sortie ; intervalle minimal et plafond de requêtes par Recording. Le sondage périodique est à éviter (§1.2, §2.3).
- **Destination** : point de retour sur le tracé (et comment le choisir) ou arrivée ; cas de la boucle et de l'aller-retour.
- **Paramètres** : `bearings` (marge 45° ou 90°, à pied ou seulement à vélo), rayons d'accroche (premier point, point de retour), comportement sur `NoSegment` / `NoRoute` (retour au mode hors ligne, ligne droite affichée ?).
- **Jeton** : réutiliser `MAPBOX_ITINERARIES_TOKEN` (300 req/min partagées avec l'éditeur) ou un jeton dédié, révocable séparément, avec son propre quota. Le palier gratuit reste partagé dans tous les cas.
- **Affichage** : ce qui apparaît sur la carte, sur l'écran de la Recording ([Écran d'une Recording en cours](https://github.com/echimine/clone-strava/issues/50)) et dans la Live Activity ([Live Activity d'une Recording : contenu, boutons et fin de vie](https://github.com/echimine/clone-strava/issues/53)) ; mention « indicatif » ou non.
- **Pause** : recalculer ou non pendant une Pause, alors que la progression suit la position.
