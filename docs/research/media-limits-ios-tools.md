# Limites vidéo de Strava et outils média d'iOS

- **Ticket** : [#158](https://github.com/echimine/clone-strava/issues/158), carte [#156](https://github.com/echimine/clone-strava/issues/156)
- **Date** : 2026-11-03
- **Portée** : faits uniquement. Les choix (format, résolution, transcodage, upload) reviennent au ticket de grilling #159 « Pipeline d'upload et de traitement des médias ».
- **Niveaux de confiance** : *élevée* (source primaire explicite), *moyenne* (source primaire partielle ou secondaire fiable), *faible* (estimation ou extrapolation).

## Résumé

1. Strava ne publie qu'une limite vidéo : **30 s**. Une vidéo plus longue est coupée automatiquement à ses 30 premières secondes. Aucune limite de poids, de format ni de résolution n'est publiée.
2. Strava n'impose **aucune limite de nombre** de médias par Activité. En revanche, l'app mobile n'en **affiche que 6** (12 sur le web). Les vidéos sont gratuites.
3. ⚠️ La cible de déploiement réelle de l'app est **iOS 17.0** (`apps/mobile/project.yml`), pas iOS 26. Toute API iOS 18, 26 ou 27 citée ici demande un `if #available`.
4. Côté iOS, le natif couvre tout : sélection mixte ordonnée sans autorisation Photos, HEIC → JPEG et miniature (ImageIO), découpe à 30 s et transcodage 1080p H.264 ou HEVC (`AVAssetExportSession`), image d'aperçu (`AVAssetImageGenerator`), upload d'un fichier en arrière-plan (`URLSession` background).
5. ⚠️ Les binaires précompilés de **sharp ne lisent pas le HEIC**. Lire du HEIC sur le serveur demande un libvips compilé avec libheif, libde265 et x265.
6. Le transcodage serveur peut être **évité entièrement** si l'iPhone envoie déjà un JPEG, un MP4 à 1080p de 30 s maximum et l'image d'aperçu. Il ne reste alors sur le serveur qu'une vérification (`HEAD`, éventuellement `ffprobe`).
7. Si le serveur transcode quand même : sur 2 vCores du VPS, compter environ **12 à 60 s de CPU par vidéo de 30 s en 1080p**, selon le preset x264 (confiance faible). Le worker actuel (`node:24-alpine`) ne contient ni ffmpeg ni sharp.

## 1. Strava : limites des médias d'Activité

| Limite | Valeur | Source | Confiance |
|---|---|---|---|
| Durée max d'une vidéo | 30 s : « Videos up to 30 seconds long are supported » | [Strava, *How do I add videos and photos*](https://support.strava.com/en-us/articles/15401859-how-do-i-add-videos-and-photos-to-my-activity) (page du 23/09/2026) | élevée |
| Vidéo plus longue | « automatically cropped to the first 30 seconds ». Pour garder un autre passage, Strava conseille de la recadrer d'abord dans la pellicule | idem, [version FR](https://support.strava.com/fr/articles/15401859-ajouter-des-videos-et-des-photos-a-votre-activite) | élevée |
| Outil de découpe dans l'app | aucun en 2022 (« no built-in trimming tool ») | [DC Rainmaker, 06/2022](https://dcrainmaker.com/2022/06/strava-adding-support.html) (secondaire) | moyenne, peut avoir changé |
| Format d'image | portrait, panoramique, paysage et carré « all supported » | article Strava ci-dessus | élevée |
| Nombre de médias | « no limit on the number of videos or photos » | idem | élevée |
| Nombre affiché | **6 sur l'app mobile**, 12 sur le web | idem | élevée |
| Poids max d'une vidéo ou d'une photo | **non documenté** | aucun article Strava trouvé | — |
| Formats de fichier acceptés (vidéo, photo d'Activité) | **non documenté**. Seule la photo de profil précise « JPG and PNG ». Une erreur peut aussi venir d'une image « too large to process », sans seuil donné | [Strava, photo de profil](https://support.strava.com/en-us/articles/15402164-how-do-i-upload-a-strava-profile-picture) | élevée pour le profil, aucune pour l'Activité |
| Résolution / qualité | **non documenté**. Des commentaires d'utilisateurs signalent une qualité dégradée, ce qui laisse supposer un ré-encodage côté Strava | commentaires sous l'article DC Rainmaker | faible |
| Vidéos en gratuit | oui : « available for all Strava users, no subscription required ». L'article Strava sur les fonctions de l'abonnement (10/09/2026) ne cite aucun média | [DC Rainmaker](https://dcrainmaker.com/2022/06/strava-adding-support.html), [Strava, fonctions de l'abonnement](https://support.strava.com/en-us/articles/15402044-strava-subscription-features) | élevée |
| Partenaire (Zwift) | 1 vidéo de 5 à 15 s et jusqu'à 5 photos ; elles apparaissent 8 à 10 min après l'enregistrement | [Strava, Zwift](https://support.strava.com/en-us/articles/15401675-zwift-photos-and-videos-on-strava) | élevée |
| Parcours d'ajout | « Modifier l'activité » → « Ajouter des photos/vidéos » → sélection multiple dans la photothèque → « Ajouter » | article Strava FR | élevée |

Comparé au cadrage de #156 (8 médias max, tout gratuit) : Strava ne plafonne pas le nombre, mais n'en montre que 6 dans l'app.

## 2. iOS : ce que permet l'app

### 2.0 Cible de déploiement

`apps/mobile/project.yml` (sur `origin/main`) fixe `deploymentTarget: iOS: "17.0"` et `IPHONEOS_DEPLOYMENT_TARGET: "17.0"`. Le `.xcodeproj` est généré par XcodeGen et ignoré par git. Le tableau ci-dessous donne pour chaque API la version iOS minimale indiquée par la documentation Apple.

### 2.1 Sélection : `PhotosPicker` (SwiftUI) et `PHPickerViewController` (UIKit)

| Fait | iOS min | Source |
|---|---|---|
| `PhotosPicker(selection:maxSelectionCount:selectionBehavior:matching:preferredItemEncoding:)` : sélection multiple, nombre max, comportement, filtre et encodage préféré | 16 | [PhotosPicker init](https://developer.apple.com/documentation/photosui/photospicker/init(selection:maxselectioncount:selectionbehavior:matching:preferreditemencoding:label:)) |
| Filtre mixte photos et vidéos : `PHPickerFilter.any(of: [.images, .videos])`. Exclusions possibles avec `.not(_:)` (`livePhotos`, `screenshots`, `slomoVideos`, `cinematicVideos`, `screenRecordings`…) | 14 | [PHPickerFilter](https://developer.apple.com/documentation/photosui/phpickerfilter-swift.struct) |
| Sélection **ordonnée** : `PhotosPickerSelectionBehavior.ordered` en SwiftUI ; `PHPickerConfiguration.Selection.ordered` en UIKit, avec badge numéroté dans l'ordre des taps | 15 / 16 | [Selection.ordered](https://developer.apple.com/documentation/photosui/phpickerconfiguration-swift.struct/selection-swift.enum/ordered), [PhotosPickerSelectionBehavior](https://developer.apple.com/documentation/photosui/photospickerselectionbehavior) |
| `selectionLimit` vaut 1 par défaut ; 0 donne le maximum supporté par le système | 14 | [selectionLimit](https://developer.apple.com/documentation/photosui/phpickerconfiguration-swift.struct/selectionlimit) |
| **Aucune autorisation Photos requise** : le picker tourne dans un processus séparé, « private by default ». Pas de `NSPhotoLibraryUsageDescription` à prévoir pour ce seul usage | 14 | [Delivering an Enhanced Privacy Experience](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app) |
| Encodage : `.current` « avoid transcoding, if possible » (on reçoit le HEIC ou le HEVC d'origine), `.compatible` « most compatible encoding even if transcoding is necessary », `.automatic` « may change in future releases » | 14 / 16 | [EncodingDisambiguationPolicy](https://developer.apple.com/documentation/photosui/photospickeritem/encodingdisambiguationpolicy), [AssetRepresentationMode](https://developer.apple.com/documentation/photosui/phpickerconfiguration-swift.struct/assetrepresentationmode) |
| Les résultats sont des placeholders : il faut charger chaque élément avec `loadTransferable(type:)`, qui rend un `Progress`. Pour les gros fichiers, Apple recommande `FileRepresentation` (copie dans un dossier de l'app). Le chargement peut échouer, par exemple sur un média iCloud sans réseau | 16 | [PhotosPickerItem](https://developer.apple.com/documentation/photosui/photospickeritem), [Bringing Photos picker to your SwiftUI app](https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app), [FileRepresentation](https://developer.apple.com/documentation/coretransferable/filerepresentation) |
| ⚠️ Le `Transferable` de `Image` ne gère que PNG et JPEG. Pour lire du HEIC ou une vidéo, il faut un type `Transferable` maison | 16 | [PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker) |
| `PHPickerConfiguration.metadataOptions` : `.removeLocation` et `.removeCaptions` retirent ces métadonnées dès le picker | **27** | [PHPickerMetadataOptions](https://developer.apple.com/documentation/photosui/phpickermetadataoptions) |

**Non vérifié** : si une vidéo a été découpée dans Photos, le picker renvoie-t-il la version découpée ? Probablement oui (représentation « current » avec ajustements), mais aucune page Apple ne le dit. Confiance moyenne.

### 2.2 Photos : HEIC → JPEG, redimensionnement, GPS

- ImageIO (`CGImageDestination`) écrit du JPEG avec `kCGImageDestinationLossyCompressionQuality` (0.0 à 1.0) et redimensionne avec `kCGImageDestinationImageMaxPixelSize`. Sans cette clé, l'image garde sa taille native ([doc 1](https://developer.apple.com/documentation/imageio/kcgimagedestinationlossycompressionquality), [doc 2](https://developer.apple.com/documentation/imageio/kcgimagedestinationimagemaxpixelsize)). iOS 4 et 8, disponible partout.
- Miniature : `CGImageSourceCreateThumbnailAtIndex` avec `kCGImageSourceThumbnailMaxPixelSize` ([doc](https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize)).
- GPS : `kCGImageMetadataShouldExcludeGPS` retire le GPS de l'EXIF et du XMP. Par défaut, le GPS est conservé. ⚠️ Cette clé ne filtre pas les données de lieu propriétaires du MakerNote ni du XMP personnalisé ([doc](https://developer.apple.com/documentation/imageio/kcgimagemetadatashouldexcludegps)).
- Autre voie : `.compatible` dans le picker fait faire la conversion par le système (§2.1).

### 2.3 Vidéo : découpe, transcodage, streaming

- `AVAssetExportSession` ([doc](https://developer.apple.com/documentation/avfoundation/avassetexportsession)) :
  - `timeRange` exporte une plage (par exemple les 30 premières secondes, comme Strava).
  - `fileLengthLimit` fixe une taille de sortie à ne pas dépasser.
  - `estimateOutputFileLength` estime la taille avant l'export.
  - `shouldOptimizeForNetworkUse` optimise le fichier pour le réseau.
- Presets ([liste](https://developer.apple.com/documentation/avfoundation/export-presets)) : `AVAssetExportPreset1920x1080` (H.264 + AAC, iOS 5), `AVAssetExportPresetHEVC1920x1080` (HEVC + AAC, iOS 11), `AVAssetExportPresetHEVCHighestQuality`, `…1280x720`, `…3840x2160`, `Passthrough`. Le système n'agrandit jamais une vidéo plus petite que le preset ([doc](https://developer.apple.com/documentation/avfoundation/avassetexportpreset1920x1080)). Apple ne publie pas le débit de ces presets.
- API d'export par version :
  - `export(to:as:isolation:)` (async) : la page indique iOS 13+.
  - `states(updateInterval:)` (progression) : **iOS 18+**.
  - `exportAsynchronously(completionHandler:)` : dépréciée en iOS 18, mais c'est la seule voie de progression sur iOS 17 ([doc](https://developer.apple.com/documentation/avfoundation/avassetexportsession/exportasynchronously(completionhandler:))).
- `AVAssetWriter` contrôle finement le débit (`AVVideoAverageBitRateKey`, [doc](https://developer.apple.com/documentation/avfoundation/avvideoaveragebitratekey)) et a aussi `shouldOptimizeForNetworkUse`. Il demande beaucoup plus de code (lecture avec `AVAssetReader`, écriture sample par sample). Les nouveaux `inputReceiver(for:)` datent d'iOS 26 ([doc](https://developer.apple.com/documentation/avfoundation/avassetwriter/inputreceiver(for:))).
- Placement du `moov` en tête : c'est ce que fait l'option `faststart` de ffmpeg (« Run a second pass to put the index (moov atom) at the beginning of the file », `ffmpeg -h muxer=mp4`). Apple ne détaille pas ce que fait `shouldOptimizeForNetworkUse`. On suppose qu'il place lui aussi le `moov` en tête (confiance moyenne, à vérifier avec `ffprobe -v trace` sur un export réel).
- ⚠️ **Export en arrière-plan** : `BGContinuedProcessingTask` (**iOS 26+**) laisse un export vidéo lancé par l'utilisateur se poursuivre en arrière-plan. La progression s'affiche dans une Live Activity, l'utilisateur peut annuler, et la tâche est tuée si l'app est fermée depuis le sélecteur d'apps. Apple cite « Exporting video » et « compressing images for social media posts » comme cas d'usage ([doc](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)). Sur iOS 17-25, rien de tel.
- Les pages consultées ne disent pas explicitement que l'encodeur matériel est utilisé. C'est le comportement attendu de VideoToolbox (confiance moyenne).

### 2.4 Image d'aperçu d'une vidéo

`AVAssetImageGenerator.image(at:)` (async, iOS 16) rend un `CGImage` ([doc](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/image(at:))). Deux réglages comptent :

- ⚠️ `appliesPreferredTrackTransform` vaut `false` par défaut : sans lui, l'aperçu d'une vidéo portrait sort pivoté ([doc](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/appliespreferredtracktransform)).
- `maximumSize` limite la taille de l'image ; il vaut zéro par défaut, soit la taille native ([doc](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/maximumsize)).

L'image s'encode ensuite en JPEG avec ImageIO (§2.2).

### 2.5 Upload en arrière-plan

- `URLSessionConfiguration.background(withIdentifier:)` (iOS 8) : les transferts se font dans un processus système et continuent quand l'app est suspendue ou terminée par le système ([doc](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))).
- Limites ([Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)) :
  - **uploads depuis un fichier uniquement** (`uploadTask(with:fromFile:)`) ; un upload depuis `Data` ou un stream échoue une fois l'app sortie ;
  - un delegate est obligatoire ;
  - ⚠️ si l'utilisateur **force la fermeture** de l'app, le système annule tous les transferts, et l'app n'est pas relancée tant que l'utilisateur ne la rouvre pas ;
  - un transfert lancé depuis l'arrière-plan est toujours traité comme `isDiscretionary`. Le système peut alors attendre le Wi-Fi ou la charge, et un limiteur de débit retarde les nouvelles tâches à chaque relance ([isDiscretionary](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/isdiscretionary)).
  - Apple conseille une seule session et plusieurs tâches lancées ensemble.
- Réveil : `application(_:handleEventsForBackgroundURLSession:completionHandler:)`, ou en SwiftUI `.backgroundTask(.urlSession(...))` (iOS 16, [doc](https://developer.apple.com/documentation/swiftui/backgroundtask/urlsession)).
- Uploads reprenables (iOS 17) : ils supposent que le serveur implémente le brouillon IETF `draft-ietf-httpbis-resumable-upload` ([doc](https://developer.apple.com/documentation/foundation/pausing-and-resuming-uploads)). Aucune doc OVH ne dit qu'Object Storage le supporte ; probablement non (confiance moyenne). Une coupure fait donc repartir le `PUT` de zéro.
- ⚠️ **Expiration de l'URL pré-signée** : S3 vérifie l'expiration « at the time of the HTTP request ». Un transfert commencé avant l'échéance continue ; une reprise après l'échéance échoue ([AWS, presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)). Le comportement d'OVH n'est pas documenté (S3-compatible, confiance moyenne). Le `presignPut` actuel dure **15 min** (`packages/core/src/storage/storage.service.ts`). Une tâche d'arrière-plan différée par le système peut donc démarrer avec une URL déjà expirée. SigV4 accepte jusqu'à 7 jours.
- Existant : l'app n'utilise aucune session `URLSession` d'arrière-plan. La file `sync_operation` est vidée hors app par un `BGAppRefreshTask` (`fr.echimine.stravaclone.sync-queue`, ADR-031 §14) ; `UIBackgroundModes: [location, fetch]`.

### 2.6 Poids typiques des fichiers iPhone

- Format de capture par défaut : HEIF / HEVC (« High Efficiency ») depuis l'iPhone 7. « Most Compatible » repasse en JPEG / H.264. iCloud Photos garde le format d'origine ; AirDrop, Messages ou un e-mail peuvent convertir en JPEG ou H.264 ([Apple, HEIF/HEVC](https://support.apple.com/en-us/116944)).
- Poids par minute de vidéo : les ordres de grandeur affichés dans Réglages > Appareil photo > Enregistrer une vidéo (HEVC : environ 60 Mo en 1080p30, 170 Mo en 4K30, 400 Mo en 4K60) ne sont publiés sur aucune page Apple. Confiance moyenne. **Une vidéo de 30 s en 4K60 pèse donc environ 200 Mo avant transcodage.**

## 3. Serveur : ffmpeg, sharp, coût CPU

### 3.1 Le VPS et le worker

- VPS OVH `vps-9ca1f319` (API OVH) : offre **VPS-3 2027**, **6 vCores, 12 Go de RAM, 100 Go de disque**. Il héberge aussi les autres apps (ADR-018). Le modèle de CPU n'est pas exposé par l'API.
- `apps/worker/Dockerfile` : `node:24-alpine`, sans ffmpeg ni sharp. Aucune dépendance média dans les `package.json`. Le compose ne fixe ni `cpus` ni `mem_limit` au worker. ADR-011 §6 : la concurrence est réglée par file, et la file `media` est prévue « plus tard ».

### 3.2 sharp (images)

- Binaires précompilés : Linux x64 glibc ≥ 2.28 **ou musl ≥ 1.2.5** (Alpine compris), CPU avec SSE4.2, Node ≥ 20.9.0 ([sharp, install](https://sharp.pixelplumbing.com/install/)).
- Formats lus : « JPEG, PNG, Ultra HDR, WebP, AVIF, TIFF, GIF and SVG (input) ». ⚠️ **Pas de HEIC** : il faut « a globally-installed libvips compiled with support for libheif, libde265 and x265 » ([sharp, heif()](https://sharp.pixelplumbing.com/api-output/#heif)).
- Débit publié (sharp 0.35.0, libvips 8.18.2) : décoder un JPEG de 2725×2225 (6 Mpx), le réduire à 720×588 et le réencoder en qualité 80 tourne à **~88 op/s sur 4 vCPU AMD EPYC 9R45** et ~52 op/s sur 4 vCPU Graviton4 ([sharp, performance](https://sharp.pixelplumbing.com/performance/)). Une photo iPhone de 12 à 24 Mpx coûte 2 à 4 fois plus de pixels, soit de l'ordre de **0,05 à 0,2 s de CPU par photo** (extrapolation, confiance faible). C'est négligeable devant la vidéo.

### 3.3 ffmpeg (vidéo)

- Alpine 3.22 : le paquet `ffmpeg` (6.1.2) dépend de `ffmpeg-libavcodec` (15,7 Mio installés), lié à `libx264`, `libx265` et `libdav1d`, mais pas à `libde265` ([ffmpeg](https://pkgs.alpinelinux.org/package/v3.22/community/x86_64/ffmpeg), [ffmpeg-libavcodec](https://pkgs.alpinelinux.org/package/v3.22/community/x86_64/ffmpeg-libavcodec)). Le décodeur HEVC natif de libavcodec suffit pour lire les vidéos iPhone. La taille totale ajoutée à l'image, toutes dépendances comprises, n'a pas été mesurée.
- Licence : GPL-2.0-or-later avec x264. À regarder seulement si l'image GHCR est distribuée publiquement ; ce n'est pas tranché ici.
- libx264 : preset `medium` par défaut, CRF pour la qualité constante (`ffmpeg -h encoder=libx264`).
- **Mesure locale** (2026-11-03, ffmpeg 8.1.1, libx264 logiciel, Apple M5 Pro). Source synthétique de 30 s à 30 i/s, `testsrc2` + bruit, encodée en HEVC comme un iPhone. Sortie H.264 CRF 23 `+faststart`, sans audio :

| Opération (clip de 30 s) | 2 threads | 6 threads |
|---|---|---|
| 1080p HEVC → 1080p H.264, `veryfast` | 5,8 s | 3,4 s |
| 1080p HEVC → 1080p H.264, `medium` | 19,6 s | 8,4 s |
| 4K HEVC → 1080p H.264, `veryfast` | 15,3 s | 8,5 s |
| Image d'aperçu JPEG (`-frames:v 1`) | 0,1 s | — |
| Remux `-c copy +faststart` (sans réencodage) | < 0,1 s | — |
| `ffprobe` (durée, codec, dimensions) | 0,04 s | — |

- **Extrapolation au VPS** (confiance faible). Hypothèse : un vCore OVH est 2 à 3 fois plus lent qu'un cœur de M5 Pro, et le contenu réel est plus ou moins dur à encoder que la source synthétique. Pour une vidéo de 30 s sur 2 vCores :
  - 1080p `veryfast` : 12 à 18 s ;
  - 1080p `medium` : 40 à 60 s ;
  - 4K → 1080p `veryfast` : 30 à 45 s.

  Pour une Activité de 8 vidéos de 30 s en 1080p `veryfast`, cela fait 1,5 à 2,5 min de 2 vCores. Pendant ce temps, l'API, le realtime, Postgres et les autres apps du VPS partagent les 6 vCores. Pour mesurer sur le VPS lui-même : `docker run --rm --cpus=2 …` avec une vraie vidéo iPhone.
- Aucun benchmark public consultable ne correspond à 2 à 6 vCores (OpenBenchmarking refuse la lecture automatisée, et ses résultats indexés portent sur des serveurs de 64 cœurs).

### 3.4 Peut-on éviter tout transcodage serveur ?

Oui, techniquement. L'iPhone produit tout ce qu'il faut avec les API natives :

| Livrable | Outil iOS | iOS min |
|---|---|---|
| Photo JPEG redimensionnée, sans GPS | ImageIO (§2.2) | 8 |
| Miniature de photo | `CGImageSourceCreateThumbnailAtIndex` | 4 |
| Vidéo MP4 1080p H.264 ou HEVC, coupée à 30 s, optimisée réseau | `AVAssetExportSession` + `timeRange` + `shouldOptimizeForNetworkUse` | 5 / 11 |
| Image d'aperçu de la vidéo | `AVAssetImageGenerator.image(at:)` + `appliesPreferredTrackTransform` | 16 |

Le serveur ne garde alors que des vérifications : taille via `HEAD` (déjà le motif d'ADR-019 §4) et, s'il faut valider le contenu, `ffprobe` (~0,04 s, mais ffmpeg dans l'image). Lire les en-têtes MP4 en Node, sans ffmpeg, reste possible mais n'a pas été évalué.

Limites de cette voie :

- le serveur fait confiance à un client qui pourrait être modifié ;
- les vidéos importées par un autre canal (backoffice, futur client) n'auraient pas de pipeline ;
- l'export sur iPhone prend du temps à l'écran (non mesuré ici) et, avant iOS 26, ne continue pas en arrière-plan.

## 4. Points actionnables pour #159 (aucun n'est tranché ici)

1. **Durée max** : couper à 30 s comme Strava (`timeRange`) ou refuser au-delà. Faut-il un outil de découpe dans l'app (Strava n'en avait pas en 2022) ?
2. **Où transcoder** : sur l'iPhone seulement (§3.4), sur le serveur seulement (ffmpeg dans le worker, file `media`, concurrence à fixer), ou les deux (iPhone + vérification serveur).
3. **Codec et résolution de sortie** : H.264 (`AVAssetExportPreset1920x1080`) ou HEVC (`AVAssetExportPresetHEVC1920x1080`), 1080p ou 720p, et poids max accepté (`fileLengthLimit` côté iOS, `HEAD` côté serveur).
4. **Format photo** : JPEG converti sur l'iPhone, ce qui évite le problème du HEIC dans sharp. Choisir la dimension max, la qualité et la taille de la miniature.
5. **Aperçu vidéo** : généré sur l'iPhone et envoyé comme un objet séparé, ou extrait sur le serveur par ffmpeg.
6. **Métadonnées** : retirer le GPS des photos (`kCGImageMetadataShouldExcludeGPS`, ou `.removeLocation` en iOS 27+), sachant que `taken_at_point` n'est pas utilisé (hors carte #156).
7. **Upload** : `URLSession` d'arrière-plan depuis un fichier, ou passage par la file `sync_operation` existante (`BGAppRefreshTask`). Durée de l'URL `PUT` pré-signée (15 min aujourd'hui, risque d'expiration avant le démarrage d'une tâche différée). Comportement après fermeture forcée.
8. **Export en arrière-plan** : `BGContinuedProcessingTask` derrière `if #available(iOS 26, *)`, ou export au premier plan avec progression (`states(updateInterval:)` iOS 18+, `exportAsynchronously` iOS 17).
9. **Cible iOS** : rester en iOS 17 avec des branches `#available`, ou relever la cible. C'est hors carte, mais cela conditionne les points 6 et 8.
10. **Affichage** : Strava montre 6 médias sur mobile ; nous en autorisons 8. Le carrousel montre-t-il les 8 ?

## 5. Non documenté ou à vérifier

| Point | Statut | Confiance |
|---|---|---|
| Poids max, formats et résolution des médias Strava | non publiés par Strava | — |
| Ré-encodage des vidéos par Strava | indices venant d'utilisateurs seulement | faible |
| Débit réel des presets `AVAssetExportPreset…1920x1080` | non publié par Apple ; mesurable sur un appareil | — |
| `shouldOptimizeForNetworkUse` place le `moov` en tête | à vérifier avec `ffprobe -v trace` | moyenne |
| Le picker renvoie la version découpée dans Photos | non documenté | moyenne |
| Expiration pré-signée vérifiée au début de la requête chez OVH | documenté par AWS seulement | moyenne |
| Uploads reprenables (brouillon IETF) chez OVH | non documenté, probablement non | moyenne |
| Modèle de CPU du VPS-3 2027 et vitesse réelle de ffmpeg dessus | non exposés ; à mesurer avec `docker run --cpus=2` | — |
| Taille ajoutée à l'image worker par `apk add ffmpeg` | non mesurée | — |
| Poids par minute des vidéos iPhone | affiché par iOS, non publié en ligne | moyenne |

## Sources

- Strava : [Add videos and photos (EN)](https://support.strava.com/en-us/articles/15401859-how-do-i-add-videos-and-photos-to-my-activity), [(FR)](https://support.strava.com/fr/articles/15401859-ajouter-des-videos-et-des-photos-a-votre-activite), [Profile picture](https://support.strava.com/en-us/articles/15402164-how-do-i-upload-a-strava-profile-picture), [Zwift photos and videos](https://support.strava.com/en-us/articles/15401675-zwift-photos-and-videos-on-strava), [Subscription features](https://support.strava.com/en-us/articles/15402044-strava-subscription-features) ; secondaire : [DC Rainmaker, 06/2022](https://dcrainmaker.com/2022/06/strava-adding-support.html).
- Apple (developer.apple.com, JSON de la documentation consulté le 2026-11-03) : PhotosPicker, PhotosPickerItem, PHPickerFilter, PHPickerConfiguration (selectionLimit, Selection, AssetRepresentationMode, metadataOptions), PHPickerMetadataOptions, PhotoKit privacy, FileRepresentation, AVAssetExportSession (et presets, `states(updateInterval:)`, `exportAsynchronously`), AVAssetWriter, AVVideoAverageBitRateKey, AVAssetImageGenerator, ImageIO (clés citées), URLSessionConfiguration background, Downloading files in the background, Pausing and resuming uploads, BGContinuedProcessingTask, SwiftUI `BackgroundTask.urlSession` ; [support Apple HEIF/HEVC](https://support.apple.com/en-us/116944).
- Serveur : [sharp install](https://sharp.pixelplumbing.com/install/), [sharp heif()](https://sharp.pixelplumbing.com/api-output/#heif), [sharp performance](https://sharp.pixelplumbing.com/performance/), [Alpine ffmpeg](https://pkgs.alpinelinux.org/package/v3.22/community/x86_64/ffmpeg), [Alpine ffmpeg-libavcodec](https://pkgs.alpinelinux.org/package/v3.22/community/x86_64/ffmpeg-libavcodec), aide intégrée `ffmpeg -h muxer=mp4` et `ffmpeg -h encoder=libx264` (ffmpeg 8.1.1), [AWS S3 presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html), API OVH `GET /vps/{serviceName}`.
- Dépôt : `apps/mobile/project.yml`, `apps/worker/Dockerfile`, `deploy/docker-compose.yml`, `packages/core/src/storage/storage.service.ts`, `apps/mobile/StravaClone/App/SyncQueueBackgroundRefresh.swift`, ADR-011, ADR-018, ADR-031 §14.
