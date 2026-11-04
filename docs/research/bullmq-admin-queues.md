# Lire et piloter les files BullMQ depuis l'API

Ticket : #194 (carte wayfinder #190 « Backoffice Nervo »). Recherche du 2026-11-04.

**Question** : comment l'API peut-elle lire et piloter les files BullMQ du worker (ADR-011) pour le backoffice, sans que `apps/admin` touche Redis (ADR-004, ADR-013) ?

**Sources primaires** : code source de BullMQ **6.3.8**, la version installée (`node_modules/.pnpm/bullmq@6.3.8…/dist/esm`, fichiers `.d.ts`, `.js` et scripts Lua) ; doc BullMQ (docs.bullmq.io) ; dépôt et registre npm de Bull Board (`felixmosh/bull-board`, `@bull-board/*` 9.11.0) ; notre code sur `main` (2c0808d) ; une lecture seule du Redis de dev local. Le Redis de prod n'a pas été consulté.

---

## 1. Ce que BullMQ 6 offre côté producteur

Une instance `Queue` suffit. L'API en a déjà une, injectée par `@InjectQueue` (`apps/api/src/bull/bull.module.ts`, connexion `REDIS` partagée, producteur seul). Aucune de ces méthodes ne demande de `Worker`.

### Lire

| Besoin | Méthode | Coût Redis (lu dans le code) |
|---|---|---|
| Compteurs par état | `queue.getJobCounts(...types)` (tous les états si vide) | **Un seul script Lua** `getCounts-1.lua` : un `LLEN` (wait, paused, active) ou un `ZCARD` (delayed, prioritized, completed, failed…) par état, donc O(1) par état. |
| Une page de jobs | `queue.getJobs(types, start, end, asc)`, ou `getFailed`, `getWaiting`, `getDelayed`, `getCompleted`, `getActive` | **Un seul script Lua** `getJobs-1.lua` en v6 : il lit les ids **et** les hashes dans le même appel, et saute les ids dont le hash a disparu entre-temps. Coût O(taille de la page). `start`/`end` sont des index à partir de 0, bornes incluses. |
| Un job | `queue.getJob(id)` et `job.getState()` | `HGETALL` sur le hash, puis un test d'appartenance par état. |
| État de la file | `queue.isPaused()`, `queue.getWorkersCount()`, `queue.getWorkers()` | `getWorkers` passe par `CLIENT LIST`, donc par toutes les connexions Redis : à éviter en polling. |
| Jobs planifiés | `queue.getJobSchedulers()`, `getJobScheduler(id)` | Renvoie `JobSchedulerJson` : `key`, `name`, `pattern` ou `every`, `tz`, **`next`** (prochaine exécution), `iterationCount`, `template`. |

Champs utiles d'un job (`classes/job.d.ts`) : `id`, `name`, `data`, `opts.attempts`, **`attemptsMade`** (incrémenté à chaque échec), `attemptsStarted`, `stalledCounter`, **`failedReason`**, **`stacktrace`** (tableau, borné par `opts.stackTraceLimit`), `timestamp`, `processedOn`, `finishedOn`, `returnvalue`.

### Piloter

| Action | Méthode | Comportement vérifié dans le code |
|---|---|---|
| Relancer un job | `job.retry(state = 'failed', { resetAttemptsMade?, resetAttemptsStarted? })` | Script `reprocessJob-7.lua`. « Only a job that has failed or completed can be retried » ; lève une erreur si le job est verrouillé ou n'est pas dans l'état attendu. **Sans `resetAttemptsMade: true`, `attemptsMade` reste à 5** : au prochain échec, le job échoue définitivement sans backoff. |
| Tout relancer | `queue.retryJobs({ state: 'failed' \| 'completed', count = 1000, timestamp })` | Boucle de scripts `moveJobsToWait-8.lua`, 1 000 jobs par appel. Efface `finishedOn`, `processedOn`, `failedReason` mais **ne remet jamais `attemptsMade` à zéro**. « Does not support jobs with priorities ». |
| Supprimer un job | `job.remove()` ou `queue.remove(id)` | Supprime le hash et toutes ses traces. |
| Purger par état | `queue.clean(graceMs, limit, type = 'completed')` | Lots de 10 000 au plus par script ; renvoie les ids supprimés. `drain()` vide wait et delayed ; `obliterate()` détruit la file (« can be slow for very large queues »). |
| Pause globale | `queue.pause()` / `resume()` / `isPaused()` | En v6, `pause-7.lua` pose `paused=1` dans le hash `meta`. La pause vaut pour **tous les workers** ; les jobs en cours terminent ; on peut toujours ajouter des jobs, qui attendent. La JSDoc parle encore d'un `RENAME` de la liste wait : elle est périmée. |
| Planifications | `upsertJobScheduler`, `removeJobScheduler(id)` | Idempotent sur l'id (déjà utilisé par le worker). |

Doc : [Getters](https://docs.bullmq.io/guide/jobs/getters), [Retrying failing jobs](https://docs.bullmq.io/guide/retrying-failing-jobs), [Removing jobs](https://docs.bullmq.io/guide/queues/removing-jobs), [Job Schedulers](https://docs.bullmq.io/guide/job-schedulers/).

---

## 2. Rétention actuelle des jobs terminés

### Règle de BullMQ

- Par défaut, un job terminé ou en échec **reste indéfiniment** dans l'ensemble `completed` ou `failed` (`interfaces/worker-options.d.ts` : « Default behavior is to keep the job in the completed set » ; [Auto-removal of jobs](https://docs.bullmq.io/guide/queues/auto-removal-of-jobs)).
- `removeOnComplete` et `removeOnFail` acceptent `true`, un nombre, ou `{ age (en secondes), count?, limit? }`. Si `age` et `count` sont tous deux donnés, le job doit respecter les deux pour être gardé (`types/keep-jobs.d.ts`).
- ⚠️ **L'éviction est paresseuse** : « BullMQ does not run a background timer […] a job is only removed once a subsequent job of the same kind (completed or failed) is processed after its age has expired » (`types/keep-jobs.d.ts`). Une file calme garde donc ses vieux jobs au-delà de l'`age` annoncé.
- ⚠️ **La rétention change la déduplication** : « a job that has been removed will not be considered part of the queue anymore, and will not affect any future jobs that could have the same Id » (doc Auto-removal). Allonger `removeOnFail` allonge donc le temps pendant lequel un `jobId` reste « pris ».

### Notre code

| File / job | Producteur | Options | Rétention réelle |
|---|---|---|---|
| `activities` / `process-activity` | API (`complete-activity.use-case.ts`), réconciliation | `DEFAULT_JOB_RETRY` (`packages/core/src/infrastructure/enqueue-unique.ts:7-12`) : 5 essais, backoff exponentiel à partir de 30 s | Terminés : **24 h** ; échecs : **7 jours** |
| `activities` / `reprocess-activity` | API (`PATCH`), réconciliation | `DEFAULT_JOB_RETRY` (`reprocess-job-enqueuer.ts`) | 24 h / 7 jours |
| `imports` / `import-activity` | API (`import-job-enqueuer.ts`) | `DEFAULT_JOB_RETRY` | 24 h / 7 jours |
| `avatars` / `copy-google-avatar` | API (`google-avatar-copy-enqueuer.ts`) | `DEFAULT_JOB_RETRY` | 24 h / 7 jours |
| `segments` / `match-segments` | worker (`process-activity.processor.ts:81-85`) | **`{ jobId }` seulement** | **Indéfinie**, avec **1 seul essai**. ADR-019 §8 dit pourtant « The job has its own retries ». |
| `activities` / `reconcile-activities` | planificateur (`reconciliation.scheduler.ts`), toutes les 10 min | modèle sans `opts` | **Indéfinie** |
| `bucket-sweep` / `bucket-sweep` | planificateur (`bucket-sweep.scheduler.ts`), chaque jour à 03:00 UTC | modèle sans `opts` | **Indéfinie** |
| `subscriptions` / `sync-subscription` | aucun pour l'instant (`HandleRevenuecatWebhookUseCase` lève `NotImplementedException`) | — | — |

Constat sur le Redis de dev (lecture seule) : `bull:activities:completed` contient **60 jobs `repeat:reconcile-activities:*`**, soit 10 h de planification réparties sur ~25 h de sessions de dev (le plus ancien n'a jamais été évincé). Leurs `opts` n'ont aucun `removeOnComplete`, et chaque hash pèse **≈ 1,2 Ko** (`MEMORY USAGE`). En prod, cela donne 144 jobs par jour, ≈ 52 000 par an, ≈ 65 Mo par an. Ce n'est pas dramatique, mais ça grossit sans fin. Or Redis tourne en `maxmemory-policy noeviction` (`deploy/redis.conf`, comme le demande [Going to production](https://docs.bullmq.io/guide/going-to-production)) : une fois la mémoire pleine, les écritures échouent au lieu d'expulser des clés.

L'historique durable vit déjà **en base**, pas dans Redis :
- `activity.processing_error` (`invalid_trace`, `empty_trace`, `processing_error`) et `activity.processing_attempts`, incrémenté à chaque tentative (`packages/db/src/schema/activities.ts:78`, `activity.repository.ts:258`) ;
- `activity_import.status`, `attempts` et le code d'erreur (`packages/contracts/src/activities/import.ts`).

Pour afficher un historique de plusieurs semaines, il vaut mieux lire Postgres. Redis sert au diagnostic récent : message, stacktrace, tentatives.

---

## 3. Piège : relancer un job BullMQ ne relance pas le domaine

`ProcessActivityUseCase.execute` sort sans rien faire si l'Activité n'est pas `processing` (`process-activity.use-case.ts:39-41` : « Deleted, already processed or failed: a replayed job is a no-op »). `ImportActivityFromFileUseCase` fait de même (`import-activity-from-file.use-case.ts:71`).

Or un `process-activity` qui échoue pour de bon passe l'Activité en `failed` (`onFailed` → `markProcessingFailed`). Un `job.retry()` brut, que ce soit le nôtre ou le bouton « Retry » de Bull Board, **termine donc en `completed` sans rien faire**, et l'Activité reste `failed`. Une vraie relance doit passer par le domaine : repasser l'entité en `processing`, puis `enqueueUnique`, qui supprime le job terminé portant le même id avant de l'ajouter de nouveau. C'est ce que fait `POST /v1/admin/activity-imports/:id/reprocess` (ADR-028 §7). ⚠️ L'équivalent pour les Activités, `POST /v1/admin/activities/:id/reprocess` (ADR-019 §6), **n'existe pas encore** : `AdminController` ne le mentionne qu'en commentaire.

`job.retry()` ne vaut donc que pour les jobs **sans garde d'état** : `match-segments`, `copy-google-avatar`, `bucket-sweep`, `reprocess-activity` (relancé sur une Activité `processed`), `reconcile-activities`.

---

## 4. Bull Board dans l'API

### État du projet

- `@bull-board/api`, `@bull-board/nestjs`, `@bull-board/express` et `@bull-board/ui` en **9.11.0**, publiés le 2026-11-01. Licence MIT, ~3 500 étoiles, dernier push le 2026-11-04, dépôt non archivé. Une vingtaine de versions 9.x depuis août 2026.
- **Compatible BullMQ 6** : peer `bullmq: "^5.56.0 || ^6.0.0"`, optionnelle, déclarée depuis la 9.0.0 (2026-08-17). BullMQ 6.0.0 est sorti le 2026-07-30.
- `@bull-board/nestjs` : peers `@nestjs/common` et `@nestjs/core` `^9 || ^10 || ^11 || ^12`, `@nestjs/bull-shared`. Nous avons Nest 11 et `@nestjs/bullmq` 11.0.5.
- `@bull-board/express` dépend de `express ^5.3.0` et `ejs ^6`. Nous avons express 5.2.1 : pnpm installera une **seconde copie d'express**.

### Montage (code de `packages/nestjs/src/bull-board.root-module.ts`)

- `BullBoardModule.forRoot({ route, adapter: ExpressAdapter, middleware, boardOptions })`, puis `forFeature({ name, adapter: BullMQAdapter, options })` par file, qui résout la `Queue` dans le conteneur Nest.
- Le module monte **un middleware Express** (`consumer.apply(middleware, adapter.getRouter()).forRoutes(route)`), pas un contrôleur. Conséquence : **`SessionGuard`, `AdminGuard` (des `CanActivate`) et le `ThrottlerGuard` global ne s'appliquent pas**. Il faut réécrire leur logique dans le `middleware` : `AuthService.getSession`, rôle `admin`, `twoFactorEnabled`, `authMethod === "password_2fa"`. Le README ne montre que `express-basic-auth`. `forRootAsync` permet d'injecter `AuthService`.
- **Chemin, le point bloquant** : le module force `adapter.setBasePath(globalPrefix + route)`, soit `/v1/admin/queues`. Le template `index.ejs` écrit `<base href="<%= basePath %>">`, et toute l'UI (client axios, `BrowserRouter basename`, assets) part de cette balise (`packages/ui/src/index.tsx`). Or le navigateur passe par le proxy Next.js, qui réécrit `/api/v1/:path*` vers `/v1/:path*` (`apps/admin/next.config.ts`). L'UI demanderait donc `/v1/admin/queues/...` sur le domaine du backoffice, ce qui tombe sur Next (et `proxy.ts`), pas sur l'API. Deux contournements :
  1. ne pas utiliser `@bull-board/nestjs`, mais `@bull-board/express` à la main dans `main.ts` : `serverAdapter.setBasePath("/api/v1/admin/queues")` (chemin public) et `expressApp.use("/v1/admin/queues", authMiddleware, serverAdapter.getRouter())` (chemin serveur) ;
  2. ajouter une réécriture Next dédiée qui conserve le chemin `/v1/admin/queues/...`.
- **Cookie** : la réécriture Next garde l'origine et transmet le cookie de session, et `proxy.ts` exclut `api` de son matcher. L'authentification par cookie marche donc, à condition d'avoir le middleware ci-dessus.
- **Ressources externes** : le template charge IBM Plex depuis `fonts.googleapis.com`. Ce n'est pas bloquant aujourd'hui (aucune CSP n'est posée), mais il y a un appel tiers.

### Ce que Bull Board expose

- Routes (`packages/api/src/routes.ts`) : lecture (files, jobs, logs, workers, planificateurs, stats Redis `INFO`, métriques) et **actions** : retry et clean par job ou par état, promote, pause et resume (par file ou toutes), **`empty`, `obliterate`, `add` (créer un job), `update-data`, création, modification et suppression de planificateurs, concurrency, rate-limit**.
- Garde-fous par file : `readOnlyMode` (coupe tout, retry compris), `allowRetries`, `allowCompletedRetries` (`queueAdapters/base.ts`). Rien d'intermédiaire, du type « retry oui, obliterate non ».
- « Retry all » fait `getJobs` page par page puis `job.retry(state)` (`handlers/retryAll.ts`), **sans `resetAttemptsMade`** : même piège qu'au §3.
- Charge : chaque onglet ouvert interroge l'API toutes les **5 s** par défaut (`pollingInterval`). Chaque tour fait `getJobCounts`, `isPaused`, la concurrence globale, le rate-limit et le nombre de planificateurs pour chaque file, plus une page de jobs. C'est négligeable à notre échelle.

---

## 5. Comparaison

| Critère | Bull Board dans l'API | Endpoints `/v1/admin/queues/*` maison |
|---|---|---|
| Authentification | Middleware Express à réécrire, hors des guards Nest et du throttler | `@UseGuards(SessionGuard, AdminGuard)` tels quels |
| Proxy Next | Contournement du `basePath` obligatoire | Rien à faire : `/api/v1/...` comme le reste |
| Relance qui a un sens métier | Non : retry brut, sans effet sur les Activités `failed` | Oui : endpoints de domaine (`activities/:id/reprocess`, `activity-imports/:id/reprocess`) |
| Actions dangereuses | Exposées sauf `readOnlyMode` (tout ou rien) | Seulement celles qu'on écrit |
| Contrats et UI | Hors `packages/contracts`, UI anglaise, design à part | Schémas Zod, OpenAPI, UI shadcn du backoffice (ADR-013) |
| Coût d'écriture | Faible pour la partie « voir » | Environ 4 endpoints et 2 écrans |
| Dépendances | 4 paquets, une seconde copie d'express, ejs | Aucune |

---

## 6. Proposition pour Nervo (à trancher dans la carte)

1. **Endpoints maison**, derrière `SessionGuard` et `AdminGuard`, dans `AdminController` ou un contrôleur `admin/queues` voisin :
   - `GET /v1/admin/queues` : pour chaque file, `getJobCounts()`, `isPaused()` et les planificateurs (`getJobSchedulers()` → `pattern`/`every`, `next`) ;
   - `GET /v1/admin/queues/:name/jobs?state=failed&page=` : `getJobs` paginé, qui renvoie id, nom, ids métier pris dans `data`, `failedReason`, `attemptsMade`/`opts.attempts`, dates et les premières lignes de `stacktrace` ;
   - `POST /v1/admin/queues/:name/jobs/:id/retry` : `job.retry('failed', { resetAttemptsMade: true })`, **refusé** pour `process-activity` et `import-activity`, qu'on renvoie vers l'endpoint de domaine ;
   - `POST /v1/admin/queues/:name/pause` et `/resume` ; éventuellement `DELETE …/jobs/:id`. Pas de `obliterate` ni de `drain`.
   - Ajouter `POST /v1/admin/activities/:id/reprocess` (ADR-019 §6), qui manque.
   - Mettre les noms de files dans une liste blanche de `packages/contracts`. `BUCKET_SWEEP_QUEUE_NAME` vit aujourd'hui dans `apps/worker` (`bucket-sweep.processor.ts:11`) : il faut le déplacer, et l'API doit `registerQueue` les files qu'elle ne produit pas (`bucket-sweep`, `segments`).
2. **Bull Board** : seulement en outil de dépannage ponctuel, par exemple via un tunnel SSH vers une instance locale. Pas monté dans l'API de prod.
3. **Rétention à changer**, dans `DEFAULT_JOB_RETRY` et partout où elle manque :
   - terminés `{ age: 7 j, count: 1000 }`, échecs `{ age: 30 j, count: 5000 }` (valeurs à valider) ;
   - `opts` des modèles des deux planificateurs : `removeOnComplete: { count: 50 }`, `removeOnFail: { count: 50 }` (`JobSchedulerTemplateOptions` les accepte) ;
   - `match-segments` : passer à `DEFAULT_JOB_RETRY`, ce qui corrige aussi l'écart avec ADR-019 §8 ;
   - ⚠️ garder la déduplication en tête : un `reprocess-activity` en échec bloque son `jobId` pendant toute la durée de `removeOnFail`, puis le balayage le retente (ADR-033 §5). Passer de 7 à 30 jours espace donc ces nouvelles tentatives d'autant ;
   - un nettoyage ponctuel (`clean(0, n, 'completed')` sur `activities`) pour les `reconcile-activities` déjà accumulés en prod.
