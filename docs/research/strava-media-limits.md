# Recherche : limites vidéo de Strava et outils média d'iOS

- **Ticket** : [#158 Limites vidéo de Strava et outils média d'iOS](https://github.com/echimine/clone-strava/issues/158) (carte wayfinder [#156](https://github.com/echimine/clone-strava/issues/156) « Photos, vidéos et avatar sur iOS »)
- **Date** : 2026-11-03
- **Question** : quelles limites Strava applique-t-il aux médias d'une Activité (durée et poids d'une vidéo, formats, résolution, nombre de médias, vidéo en gratuit) ; que permet iOS côté app (sélection mixte, HEIC → JPEG, transcodage H.264/HEVC, image d'aperçu, upload en arrière-plan vers une URL S3 pré-signée) ; et que coûtent ffmpeg / sharp dans le worker Node sur le VPS ?
- **Contexte déjà décidé** : 8 médias max par Activité, photos et vidéos mélangées, tout gratuit (vidéos comprises), carrousel carte + médias comme Strava, Galerie sur le profil.
- **Sources** : centre d'aide Strava (support.strava.com) ; documentation Apple lue au format JSON servi par `developer.apple.com/tutorials/data/documentation/…` (même contenu que les pages `developer.apple.com/documentation/…` citées) ; article d'assistance Apple ; documentation sharp ; documentation FFmpeg (fichiers `doc/*.texi` du dépôt officiel, ffmpeg.org refusant la connexion depuis cette machine) ; APKBUILD Alpine de ffmpeg ; documentation AWS S3 et OVHcloud. Tout a été lu le **2026-11-03**. Les citations sont verbatim.
- **Non vérifié** : rien n'a été testé sur iPhone. Le Community Hub de Strava renvoie `403` aux outils de lecture : ce qui en vient est signalé comme tel. Le seul chiffre mesuré (coût ffmpeg) l'a été sur un Mac, pas sur le VPS.

Conventions : **Fait** = ce que dit une source, avec son lien. **Recommandation** = mon avis pour Nervo, à trancher dans la carte.

---

## TL;DR

1. **Strava : vidéos de 30 s max**, recadrées automatiquement aux 30 premières secondes ; **aucune limite** de nombre de médias par Activité, mais l'app mobile n'en affiche que 6 et le web 12. Strava ne publie **ni poids max, ni formats, ni résolution**.
2. **Strava : la vidéo est gratuite.** La liste officielle des fonctions de l'abonnement (septembre 2026) ne mentionne ni photo ni vidéo ; au lancement (juin 2022) l'upload vidéo était annoncé gratuit pour tous.
3. **iOS : `PhotosPicker` (iOS 16+) fait la sélection mixte photo + vidéo** avec `.any(of: [.images, .videos])`, un `maxSelectionCount` (donc 8 moins les médias déjà présents) et sans autorisation d'accès à la photothèque (le picker tourne hors processus).
4. **iOS : HEIC → JPEG** se fait soit en demandant l'encodage `.compatible` au picker, soit (mieux) avec ImageIO (`CGImageDestination`, qualité, taille max en pixels, suppression du GPS).
5. **iOS : transcodage** avec `AVAssetExportSession` : presets documentés `AVAssetExportPreset1280x720` et `1920x1080` (H.264 + AAC), `AVAssetExportPresetHEVC1920x1080` (HEVC + AAC). **Pas de preset HEVC 720p.** `timeRange` coupe à 30 s, `fileLengthLimit` borne le poids. `export(to:as:)` (async) est rétroporté jusqu'à iOS 13, donc utilisable avec notre cible iOS 17.
6. **iOS : aperçu vidéo** avec `AVAssetImageGenerator.image(at:)` (iOS 16+), `appliesPreferredTrackTransform = true` pour les vidéos en portrait, `maximumSize` pour la taille.
7. **iOS : upload en arrière-plan** avec `URLSessionConfiguration.background` + `uploadTask(with:fromFile:)` : seul l'upload **depuis un fichier** survit à la sortie de l'app, le système peut retarder le transfert, et un utilisateur qui tue l'app annule tout. L'URL pré-signée doit donc vivre bien plus que les 15 min actuelles des traces (S3 accepte jusqu'à 7 jours).
8. **iOS 26 : `BGContinuedProcessingTask`** permet de finir un export vidéo lancé par l'utilisateur même si l'app passe en arrière-plan (Live Activity système, annulable). **iOS 27** ajoute l'export reprenable (`configureForResumableExport()`) et l'option du picker `removeLocation`.
9. **Serveur : sharp** tourne sur notre image `node:24-alpine` (binaires précompilés musl), ~88 images/s sur 4 vCPU dans le benchmark officiel, mais **ne lit pas le HEIC** sans libvips recompilée : l'app doit envoyer du JPEG. **ffmpeg** s'installe par `apk add ffmpeg` (x264/x265 inclus, licence GPL) ; mesuré sur Mac M5 Pro, transcoder 30 s de 1080p en 720p prend 5,6 s sur un thread (preset `veryfast`), 18,5 s en `medium`.
10. **Recommandation** : faire le travail lourd **sur l'iPhone** (vidéo ≤ 30 s, H.264 720p via preset, JPEG ≤ 2048 px sans GPS, poster JPEG) et garder le worker pour des contrôles légers (ffprobe, vignettes sharp). ffmpeg en transcodage serveur seulement si la qualité des exports iOS déçoit.

---

## 1. Strava

### Faits

| Sujet | Ce que dit Strava | Source |
|---|---|---|
| Durée max d'une vidéo | *« Videos up to 30 seconds long are supported. »* ; *« videos longer than 30 seconds will be automatically cropped to the first 30 seconds »*, sauf si l'athlète coupe lui-même avant dans sa pellicule | [Adding Videos and Photos to Your Activity](https://support.strava.com/en-us/articles/15401859-adding-videos-and-photos-to-your-activity) (daté du 23 septembre 2026) |
| Nombre de médias | *« There's no limit on the number of videos or photos you can attach to your activity. »* ; *« activities on the mobile app will display only 6, while the web will show 12 »* | même article |
| Formats d'image | *« Portrait, panoramic, landscape, and square aspect ratios are all supported. »* | même article |
| Poids max, formats de fichier, résolution | **Non documentés** : l'article n'en parle pas, aucune autre page d'aide trouvée | même article ; recherche sur support.strava.com |
| Gratuit ou abonnement | La page officielle de l'abonnement liste segments, entraînement, itinéraires, défis de groupe, Beacon, météo, *« Custom app icons »*… **Aucune mention de photo ou de vidéo.** | [What Features Are Included in a Strava Subscription?](https://support.strava.com/en-us/articles/15402044-what-features-are-included-in-a-strava-subscription) (daté du 10 septembre 2026) |
| Gratuit au lancement | *« the ability to watch and upload videos is free for all athletes (i.e., not part of the subscription) »* ; *« there's no limit on how many videos that are included with posts »* (16 juin 2022, article de presse, pas Strava directement) | [endurance.biz, 16/06/2022](https://endurance.biz/2022/industry-news/rollout-of-video-uploads-for-all-strava-athletes/) |
| Vidéos Zwift | *« One video between five and fifteen seconds and up to five photos »* envoyés automatiquement après la sauvegarde | [Zwift Photos and Videos on Strava](https://support.strava.com/hc/en-us/articles/13012230433805-Zwift-Photos-and-Videos-on-Strava) |

Non vérifié (Community Hub, page en `403`, vu seulement dans des résumés de recherche) : la demande « vidéos plus longues pour les abonnés » serait marquée *« Not Currently Planned »* ([idée 19748](https://communityhub.strava.com/t5/ideas/increasing-the-length-of-video-for-subscribers/idi-p/19748)) ; la galerie du profil n'afficherait que les 100 médias les plus récents ([fil « 100-image/video limitation »](https://communityhub.strava.com/strava-features-chat-5/100-image-video-limitation-491)).

### Recommandations

- Garder **30 s par vidéo** : c'est la limite Strava, elle borne le poids et le coût, et la coupe automatique aux 30 premières secondes est simple à faire sur l'iPhone (§ 3).
- Notre plafond de **8 médias** est plus strict que Strava (illimité) mais supérieur à ce que son app mobile montre (6). Cohérent avec un carrousel.
- Strava ne publie pas de poids max : on fixe le nôtre (§ 6).

---

## 2. iOS : sélectionner photos et vidéos

### Faits

- **`PhotosPicker`** (SwiftUI, PhotosUI) : iOS 16.0+. *« Use the Photos picker view to browse and select images and videos from the photo library. The view contains methods for single selection and multiple selection. »* ([PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker))
- Initialiseur multi-sélection : `init(selection:maxSelectionCount:selectionBehavior:matching:preferredItemEncoding:label:)`, iOS 16.0+ ([doc](https://developer.apple.com/documentation/photosui/photospicker/init(selection:maxselectioncount:selectionbehavior:matching:preferreditemencoding:label:))).
- **Filtre mixte** : `PHPickerFilter` a `images`, `videos`, et `any(of:)` : *« Returns a new filter formed by OR-ing the filters in a given array. »* ; il a aussi `not(_:)`, `screenRecordings`, `slomoVideos`, `livePhotos`… ([PHPickerFilter](https://developer.apple.com/documentation/photosui/phpickerfilter-swift.struct)). Exemple Apple : `matching: .any(of: [.images, .not(.screenshots)])`.
- **Équivalent UIKit** : `PHPickerViewController` (iOS 14+), `PHPickerConfiguration.selectionLimit` : *« The default value is `1`. Setting the value to `0` sets the selection limit to the maximum that the system supports. »* ([selectionLimit](https://developer.apple.com/documentation/photosui/phpickerconfiguration-swift.struct/selectionlimit))
- **Pas d'autorisation photothèque** : le picker *« supports search and multiple selection of photos and videos »* et *« Because the system manages its life cycle in a separate process, it's private by default. The user doesn't need to explicitly authorize your app to select photos »* ([Delivering an Enhanced Privacy Experience in Your Photos App](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app)).
- **Les résultats sont des placeholders** : *« The selection results you get are placeholder objects. A `PhotosPickerItem` conforms to `Transferable` »* ; *« A failure can occur when the system attempts to retrieve the data. For example, if the picker tries to download data from iCloud Photos without a network connection. »* ([PhotosPickerItem](https://developer.apple.com/documentation/photosui/photospickeritem))
- **Charger une vidéo comme fichier** : *« When handling many items at the same time, or large assets, use `FileRepresentation` to load assets as files and reduce memory usage. When loading assets as files, copy them to an app directory and remove them when they're no longer needed. »* ([Bringing Photos picker to your SwiftUI app](https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app)). L'exemple `FileRepresentation` d'Apple copie `received.file` dans le bloc `importing:` ([FileRepresentation](https://developer.apple.com/documentation/coretransferable/filerepresentation)).
- **`Image` ne suffit pas** : *« `Image` supports only PNG and JPEG file types through its `Transferable` conformance. To support other image types, create a custom `Transferable` model. »* ([PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker))
- **Encodage demandé au picker** (`preferredItemEncoding`, type `PhotosPickerItem.EncodingDisambiguationPolicy`) : `automatic` *« chooses the best encoding »*, `current` *« chooses the current encoding to avoid transcoding, if possible »*, `compatible` *« chooses the most compatible encoding even if transcoding is necessary »* ([EncodingDisambiguationPolicy](https://developer.apple.com/documentation/photosui/photospickeritem/encodingdisambiguationpolicy)). Même chose côté UIKit avec `PHPickerConfiguration.AssetRepresentationMode` ([doc](https://developer.apple.com/documentation/photosui/phpickerconfiguration-swift.struct/assetrepresentationmode)).
- **iOS 27** : `PHPickerConfiguration.metadataOptions` (`PHPickerMetadataOptions`), avec `removeLocation` (*« Remove location metadata. »*) et `removeCaptions` ; iOS 27.0+ seulement ([PHPickerMetadataOptions](https://developer.apple.com/documentation/photosui/phpickermetadataoptions)).
- **Formats de capture de l'iPhone** : HEIF pour les photos, HEVC pour les vidéos en « High Efficiency » ; en « Most Compatible », *« All new photos and videos will now use JPEG or H.264 format. »* ([Using HEIF or HEVC media on Apple devices](https://support.apple.com/en-us/116944), 5 décembre 2025). Il faut donc s'attendre à recevoir du HEIC et du HEVC.
- Cible du projet : `apps/mobile/project.yml` fixe `deploymentTarget iOS "17.0"`.

### Recommandations

- `PhotosPicker` en SwiftUI, `matching: .any(of: [.images, .videos])`, `maxSelectionCount: 8 - médiasDéjàPrésents`, `selectionBehavior: .ordered` pour garder l'ordre du carrousel.
- Charger avec `preferredItemEncoding: .current` (pas de transcodage système à pleine résolution) et un `Transferable` maison en `FileRepresentation` copié dans `Caches/`, puis faire notre propre conversion (§ 3 et § 4). Prévoir l'échec iCloud hors ligne.
- `removeLocation` derrière `if #available(iOS 27, *)` ne suffit pas pour iOS 17 à 26 : supprimer le GPS nous-mêmes (§ 3).

---

## 3. iOS : photos HEIC → JPEG

### Faits

- `UIImage.jpegData(compressionQuality:)` renvoie du JPEG ou `nil` *« if the image has no data or if the underlying `CGImageRef` contains data in an unsupported bitmap format »* ([jpegData](https://developer.apple.com/documentation/uikit/uiimage/jpegdata(compressionquality:))). Passer par `UIImage` décode toute l'image en mémoire.
- ImageIO : `CGImageDestination` *« outputs data to a URL, a `CFData` object, or a `CGDataConsumer` object »* et peut *« add metadata to your images »* ([CGImageDestination](https://developer.apple.com/documentation/imageio/cgimagedestination)).
- `kCGImageDestinationLossyCompressionQuality` : de `0.0` (compression max) à `1.0` ([doc](https://developer.apple.com/documentation/imageio/kcgimagedestinationlossycompressionquality)).
- `kCGImageDestinationImageMaxPixelSize` : *« If present, the destination rescales the image as needed to fit within the maximum width and height. »* ([doc](https://developer.apple.com/documentation/imageio/kcgimagedestinationimagemaxpixelsize))
- `kCGImageSourceThumbnailMaxPixelSize` + `kCGImageSourceCreateThumbnailWithTransform` (*« rotate and scale the thumbnail image to match the image's orientation »*, `false` par défaut) avec `CGImageSourceCreateThumbnailAtIndex` ([MaxPixelSize](https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize), [WithTransform](https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailwithtransform)).
- `kCGImageMetadataShouldExcludeGPS` : *« whether to exclude GPS metadata from EXIF data or the corresponding XMP tags »*, `false` par défaut ; *« This flag doesn't filter any proprietary location data in the manufacturer's EXIF MakerNote or in custom XMP properties. »* ([doc](https://developer.apple.com/documentation/imageio/kcgimagemetadatashouldexcludegps))

### Recommandations

- Conversion par ImageIO, sans `UIImage` : `CGImageSource` sur le fichier HEIC → `CGImageDestination` JPEG, `ImageMaxPixelSize` **2048**, qualité **0,8**, orientation appliquée, GPS exclu. 2048 px suffit pour un plein écran d'iPhone ; ordre de grandeur attendu quelques centaines de Ko (non mesuré).
- Le GPS d'une photo prise chez soi est une fuite plus précise que la carte de l'Activité (qui peut avoir des zones de confidentialité) : l'exclure par défaut.

---

## 4. iOS : transcodage vidéo et image d'aperçu

### Faits : `AVAssetExportSession`

- *« An object that exports assets in a format that you specify using an export preset. »* iOS 4+ ([AVAssetExportSession](https://developer.apple.com/documentation/avfoundation/avassetexportsession)).
- Presets documentés ([Export presets](https://developer.apple.com/documentation/avfoundation/export-presets)) :

| Preset | Contenu | Source |
|---|---|---|
| `AVAssetExportPreset1280x720` | *« a 1280 by 720 movie that contains H.264 video and AAC audio »* ; *« The system doesn't scale movies up from a smaller size. »* | [doc](https://developer.apple.com/documentation/avfoundation/avassetexportpreset1280x720) |
| `AVAssetExportPreset1920x1080` | *« a 1920 by 1080 movie that contains H.264 video and AAC audio »*, pas d'agrandissement | [doc](https://developer.apple.com/documentation/avfoundation/avassetexportpreset1920x1080) |
| `AVAssetExportPresetHEVC1920x1080` | *« a 1920 by 1080 movie that contains HEVC video and AAC audio »* (iOS 11+) | [doc](https://developer.apple.com/documentation/avfoundation/avassetexportpresethevc1920x1080) |
| `AVAssetExportPresetMediumQuality` / `HighestQuality` | H.264 + AAC, taille non précisée | [Medium](https://developer.apple.com/documentation/avfoundation/avassetexportpresetmediumquality), [Highest](https://developer.apple.com/documentation/avfoundation/avassetexportpresethighestquality) |

  Les presets HEVC de taille commencent à 1920x1080 : **aucun preset HEVC 1280x720**. Apple ne documente **pas le débit** des presets.
- Réglages utiles : `timeRange` (*« The time range of the source asset to export. »*), `fileLengthLimit` (*« The file length that the output of the session must not exceed. »*), `shouldOptimizeForNetworkUse`, `estimatedOutputFileLength`, `estimateMaximumDuration(completionHandler:)` ([timeRange](https://developer.apple.com/documentation/avfoundation/avassetexportsession/timerange), [fileLengthLimit](https://developer.apple.com/documentation/avfoundation/avassetexportsession/filelengthlimit), [shouldOptimizeForNetworkUse](https://developer.apple.com/documentation/avfoundation/avassetexportsession/shouldoptimizefornetworkuse)).
- `export(to:as:isolation:)` (async) : déclaré `@backDeployed(before: … iOS 26.0 …)`, disponible depuis iOS 13 ; il lève une erreur à l'annulation ou si le type de fichier n'est pas dans `supportedFileTypes` ([doc](https://developer.apple.com/documentation/avfoundation/avassetexportsession/export(to:as:isolation:))). `exportAsynchronously(completionHandler:)` est **déprécié depuis iOS 18** ([doc](https://developer.apple.com/documentation/avfoundation/avassetexportsession/exportasynchronously(completionhandler:))). `states(updateInterval:)` (progression) : iOS 18+.
- **iOS 27** : `configureForResumableExport()` *« validates that the export session's current configuration supports resumption and checks the temporary directory for any partial results from previous export attempts »* ([doc](https://developer.apple.com/documentation/avfoundation/avassetexportsession/configureforresumableexport())).

### Faits : `AVAssetWriter`

- *« You use an asset writer to write media to file formats such as the QuickTime movie file format and MPEG-4 file format. […] It can reencode media samples it writes to the output file »* ; *« An asset writer is a single-use object that writes one output file. »* ([AVAssetWriter](https://developer.apple.com/documentation/avfoundation/avassetwriter))
- `AVOutputSettingsAssistant` construit les réglages audio/vidéo à partir d'un preset (ex. `preset1920x1080`), à utiliser tels quels ou à personnaliser ; renseigner `sourceVideoFormat` *« ensures that the assistant generates settings that don't scale up video frames »* ([doc](https://developer.apple.com/documentation/avfoundation/avoutputsettingsassistant)).
- Débit réglable avec `AVVideoCompressionPropertiesKey` → `AVVideoAverageBitRateKey` (bits par seconde) ([doc](https://developer.apple.com/documentation/avfoundation/avvideocompressionpropertieskey), [doc](https://developer.apple.com/documentation/avfoundation/avvideoaveragebitratekey)). C'est le seul moyen documenté d'imposer un débit ou un HEVC 720p.

### Faits : image d'aperçu

- `AVAssetImageGenerator` : *« extract images from a video asset at particular times within its timeline »* ([doc](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator)).
- `image(at:)` (async, iOS 16+) renvoie l'image et l'heure réelle ([doc](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/image(at:))).
- `appliesPreferredTrackTransform` : `false` par défaut, *« This class only supports rotation by 90, 180, or 270 degrees. »* ([doc](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/appliespreferredtracktransform)). Sans lui, une vidéo tournée en portrait donne un aperçu couché.
- `maximumSize` : `zero` par défaut (taille native) ; sinon l'image est réduite pour tenir dans la boîte ([doc](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/maximumsize)).

### Faits : finir le travail si l'app passe en arrière-plan

- `BGContinuedProcessingTask` (iOS 26.0+) : *« A task that starts in the foreground and can continue running in the background as needed. »* ; *« The system displays the progress of this task in a Live Activity and a person can cancel it »* ; le système peut l'arrêter sous contrainte de ressources et tue d'abord les tâches qui progressent peu ([doc](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)).
- La demande doit venir d'une action de l'utilisateur, et Apple cite en exemple *« Exporting video in a film-editing app »* et *« Creating thumbnails for a new batch of photo uploads »* ([Performing long-running tasks on iOS and iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)).

### Recommandations

- **H.264 1280x720** via `AVAssetExportPreset1280x720` pour le MVP : un seul appel, lisible partout (backoffice web compris), pas d'agrandissement des petites vidéos. `timeRange` = 30 premières secondes (comportement Strava), `fileLengthLimit` comme garde-fou, `shouldOptimizeForNetworkUse = true`, sortie `.mp4`.
- HEVC 1080p (`AVAssetExportPresetHEVC1920x1080`) reste une option si la qualité 720p déçoit : Apple dit seulement que HEVC offre une meilleure compression que H.264 (gain non chiffré, [article 116944](https://support.apple.com/en-us/116944)), mais lecture HEVC à vérifier sur le backoffice web. HEVC 720p demanderait `AVAssetWriter` : pas pour le MVP.
- Mesurer sur iPhone le poids réel d'une vidéo de 30 s avec le preset 720p avant de fixer la limite serveur (Apple ne publie pas le débit).
- Aperçu : `AVAssetImageGenerator` à ~0 s (ou 1 s), `appliesPreferredTrackTransform = true`, `maximumSize` 1280 px, encodé en JPEG comme une photo et envoyé avec la vidéo. Le feed et la Galerie affichent ce poster sans télécharger la vidéo.
- Export sous `BGContinuedProcessingTask` quand `#available(iOS 26, *)`, sinon `beginBackgroundTask` comme pour l'upload des traces (ADR-031) ; l'export reprenable d'iOS 27 en bonus plus tard.

---

## 5. iOS : upload en arrière-plan vers une URL S3 pré-signée

### Faits : `URLSession` background

- `URLSessionConfiguration.background(withIdentifier:)` : *« A session configured with this object hands control of the transfers over to the system, which handles the transfers in a separate process. In iOS, this configuration makes it possible for transfers to continue even when the app itself is suspended or terminated. »* ([doc](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)))
- Même page : *« If the user terminates the app from the multitasking screen, the system cancels all of the session's background transfers. »* ; pour de gros volumes *« you are encouraged to set the value of this property [`isDiscretionary`] to `true` »*.
- `uploadTask(with:fromFile:)` : *« An HTTP upload request is any request that contains a request body, such as a `POST` or `PUT` request. »* ([doc](https://developer.apple.com/documentation/foundation/urlsession/uploadtask(with:fromfile:)))
- Limites ([Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)) : *« Only upload tasks from a file are supported (uploads from data instances or a stream fail after the app exits). »* ; la session doit avoir un délégué ; *« Redirects are always followed. »*
- Délais : *« In cases where the transfer is initiated while the app is in the background, the session configuration's `isDiscretionary` property is treated as being `true`. »* (même article) ; avec `isDiscretionary`, *« the system might delay transferring large files until the device is plugged in and connected to the network via Wi-Fi »* ([isDiscretionary](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/isdiscretionary)).
- Limiteur : quand l'app relance une tâche depuis l'arrière-plan, *« the task doesn't begin until the delay expires. The delay increases each time the system resumes or relaunches your app. »* Apple conseille *« a small number of background sessions — ideally just one »* et de lancer beaucoup de tâches à la fois ; le délai revient à 0 au passage au premier plan (même article).
- Réveil de l'app : `sessionSendsLaunchEvents` (`true` par défaut) puis `application(_:handleEventsForBackgroundURLSession:completionHandler:)` ; en SwiftUI, la tâche `.urlSession` du modificateur `backgroundTask` (iOS 16+) ([sessionSendsLaunchEvents](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/sessionsendslaunchevents), [handleEventsForBackgroundURLSession](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:handleeventsforbackgroundurlsession:completionhandler:)), [urlSession](https://developer.apple.com/documentation/swiftui/backgroundtask/urlsession)).

### Faits : URL pré-signée

- *« Using a presigned URL will allow an upload without requiring another party to have AWS security credentials or permissions. »* ; un objet de même clé est remplacé ; *« the expiration time for presigned URLs can be set as high as 7 days »* ; en cas de `SignatureDoesNotMatch`, vérifier entre autres que *« the content type in your upload request matches the content type specified when generating the URL »* ([Uploading objects with presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html)).
- OVHcloud Object Storage : URL pré-signées `GET`, `PUT`, `HEAD`, `DELETE` supportées en région et en Local Zone ([Object Storage - Compliance](https://docs.ovhcloud.com/en/guides/storage-and-backup/object-storage/s3-s3-compliancy)).

### État du projet

- ADR-019 : URL pré-signée `PUT` **valable 15 minutes**, content type imposé ; renouvellement par `POST /v1/activities/:id/upload-url` ; `403` du bucket = URL expirée (ADR-008).
- ADR-008 amendé par ADR-031 : la trace utilise une `URLSession` **normale** sous `beginBackgroundTask`, car *« A background session would delay the upload past the URL's 15 minutes for a file of a few hundred KB. »*

### Recommandations

- **Photos et posters** (quelques centaines de Ko) : même mécanique que la trace (session normale + `beginBackgroundTask`, URL de 15 min, reprise au prochain déclencheur).
- **Vidéos** (plusieurs Mo) : session background unique, `uploadTask(with:fromFile:)` depuis le fichier exporté dans `Caches/`, `isDiscretionary = false` quand l'envoi part du premier plan. L'URL doit couvrir le retard possible du système : **durée de vie longue (par exemple 24 h)**, et en cas de `403` redemander une URL comme aujourd'hui. Clé et content type (`video/mp4`) imposés par l'API, comme pour la trace.
- Une Activité n'est « complète » côté médias que quand l'API a vu chaque objet (`HEAD`, comme `complete` pour la trace) : un média dont l'upload a été annulé (app tuée) doit pouvoir être renvoyé ou abandonné.

---

## 6. Serveur : sharp et ffmpeg dans le worker

### Faits : sharp

- Binaires précompilés pour *« Linux x64 (glibc >= 2.28, musl >= 1.2.5, CPU with SSE4.2) »* ; formats *« JPEG, PNG, Ultra HDR, WebP, AVIF, TIFF, GIF and SVG (input) »* ; prérequis *« Node.js >= 20.9.0 »* ([Installation](https://sharp.pixelplumbing.com/install)).
- **HEIC** : *« Support for patent-encumbered HEIC images using `hevc` compression requires the use of a globally-installed libvips compiled with support for libheif, libde265 and x265. »* ([Output options](https://sharp.pixelplumbing.com/api-output)). Les entrées acceptées listées par le constructeur sont *« JPEG, PNG, WebP, AVIF, GIF, SVG or TIFF »* ([Constructor](https://sharp.pixelplumbing.com/api-constructor)).
- Allocateur : *« The default memory allocator on most glibc-based Linux systems (e.g. Debian, Red Hat) is unsuitable for long-running, multi-threaded processes »* ; musl n'est pas concerné ([Installation](https://sharp.pixelplumbing.com/install)). Notre worker est sur `node:24-alpine` (musl) : `apps/worker/Dockerfile`.
- Performance : sur *« AWS EC2 us-west-2 c8a.xlarge (4x AMD EPYC 9R45) »*, décoder un JPEG 2725x2225, le réduire en 720x588 et le réencoder : **≈ 88 opérations/s** pour sharp (jimp 3,4/s, ImageMagick 16/s) ; parallélisme borné par `UV_THREADPOOL_SIZE`, 4 par défaut ([Performance](https://sharp.pixelplumbing.com/performance)).
- Métadonnées : *« By default all metadata will be removed, which includes EXIF-based orientation. »* ; JPEG qualité 80 par défaut ; `limitInputPixels` par défaut `268402689` ([Output options](https://sharp.pixelplumbing.com/api-output), [Constructor](https://sharp.pixelplumbing.com/api-constructor)).

### Faits : ffmpeg

- Alpine : paquet `ffmpeg` **9.0.2**, construit avec `--enable-gpl`, `--enable-libx264`, `--enable-libx265`, licence `GPL-2.0-or-later AND LGPL-2.1-or-later` ([APKBUILD](https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/community/ffmpeg/APKBUILD)).
- `libx264` : options `preset` (*« Set the encoding preset. »*), `crf` (*« Set the quality for constant quality mode. »*), `threads` (*« Number of encoding threads. »*) ; le muxer MP4 `faststart` *« Run a second pass moving the index (moov atom) to the beginning of the file »*, désactivé par défaut ([encoders.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/encoders.texi), [muxers.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/muxers.texi)).
- Le wrapper Node le plus connu, `fluent-ffmpeg`, est **archivé depuis le 22 mai 2025** : *« This library is no longer maintained and no longer works properly with recent ffmpeg versions. »* ([dépôt](https://github.com/fluent-ffmpeg/node-fluent-ffmpeg)). Appeler `ffmpeg` / `ffprobe` via `child_process.spawn` suffit.
- VPS : OVH VPS-3, **6 vCores, 12 Go de RAM**, partagé avec les autres apps (fiche `echimine-doc/vps/vps-ovh-gra-01.md`).

### Mesure indicative (pas sur le VPS)

Sur un Mac Apple M5 Pro, ffmpeg 8.1.1 Homebrew : clip synthétique de 30 s, 1080p30, ~12 Mbit/s (ordre de grandeur d'un iPhone), transcodé en 720p H.264 `crf 23`, `maxrate 4M`, AAC 128k, `+faststart` :

| Preset | Threads | Durée |
|---|---|---|
| `veryfast` | 1 | 5,6 s |
| `veryfast` | 2 | 2,5 s |
| `medium` | 1 | 18,5 s |
| `medium` | 2 | 10,1 s |
| Poster (1 image JPEG 720p) | — | 0,06 s |

Un vCore de VPS partagé est nettement plus lent qu'un cœur M5 Pro : compter plusieurs fois ces durées (estimation, non mesurée). Le script est reproductible avec `ffmpeg -f lavfi -i testsrc2…`.

### Recommandations

- **Pas de transcodage serveur au MVP** : l'iPhone exporte déjà en H.264 720p ≤ 30 s (l'aide Strava ne dit pas si sa coupe à 30 s se fait sur le téléphone ou sur ses serveurs). Le worker reste léger et le VPS partagé n'est pas exposé à des pics CPU.
- **Worker, file `media`** (prévue par ADR-011) : `ffprobe` sur chaque vidéo reçue (codec, durée ≤ 30 s + marge, dimensions) pour refuser ce qui ne respecte pas le contrat ; sharp pour les vignettes des photos et posters (taille feed, taille Galerie), entrée JPEG uniquement. Concurrence de la file à 1 ou 2.
- Si un jour on transcode côté serveur (vidéos venant d'ailleurs que l'app, qualité iOS décevante) : `apk add ffmpeg` dans l'image du worker, `libx264 -preset veryfast -crf 23 -movflags +faststart`, `-threads 2`, concurrence 1 ; vérifier la licence GPL (outil appelé en processus séparé, non lié au code).
- **Limites Nervo proposées** : 8 médias ; vidéo ≤ 30 s, H.264 720p (MP4), poids ≤ 50 Mo par vidéo (à recaler après mesure sur iPhone) ; photo JPEG ≤ 2048 px, ≤ 5 Mo ; poster JPEG ≤ 1280 px. L'API refuse au moment de la demande d'URL ce qui dépasse le nombre, le worker refuse ce qui ne respecte pas le contrat.

---

## Questions ouvertes pour la carte #156

- Débit réel du preset `AVAssetExportPreset1280x720` sur une vidéo de 30 s : à mesurer sur iPhone, il fixe la limite de poids.
- H.264 720p ou HEVC 1080p : dépend de la lecture HEVC sur le backoffice et de la qualité perçue.
- Coupe automatique aux 30 premières secondes (Strava) ou écran de découpe : la première suffit au MVP.
- Durée de vie de l'URL pré-signée vidéo (24 h proposé) et comportement si l'utilisateur tue l'app pendant l'upload.
