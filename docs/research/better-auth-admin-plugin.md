# Recherche : plugin `admin` de Better Auth (bannissement, sessions, liste des utilisateurs)

- **Ticket** : [#191](https://github.com/echimine/clone-strava/issues/191) (carte [#190](https://github.com/echimine/clone-strava/issues/190) « Backoffice Nervo »)
- **Date** : 2026-11-04
- **Version étudiée** : `better-auth@1.7.6`, épinglée dans `apps/api/package.json` et `packages/core/package.json`, et réellement installée (`apps/api/node_modules/better-auth/package.json` → `"version": "1.7.6"`).
- **Portée** : des faits uniquement. Aucune décision n'est prise ici ; quand un fait ouvre une option, elle est listée.

## Sources

Par ordre d'autorité :

1. **Code source installé** (`node_modules/.pnpm/better-auth@1.7.6_*/node_modules/better-auth/dist/`, abrégé `dist/`) :
   - `dist/plugins/admin/{admin,routes,schema,error-codes,has-permission}.mjs`, `dist/plugins/admin/access/statement.mjs`, `dist/plugins/admin/types.d.mts`
   - `dist/db/internal-adapter.mjs`, `dist/db/with-hooks.mjs`
   - `dist/api/index.mjs` (routeur, `disabledPaths`), `dist/api/routes/session.mjs`, `dist/api/routes/sign-in.mjs`, `dist/api/routes/callback.mjs`, `dist/api/middlewares/origin-check.mjs`
   - `dist/plugins/bearer/index.mjs`, `dist/plugins/email-otp/routes.mjs`, `dist/oauth2/link-account.mjs`
   - `@better-auth/core@1.7.6` : `dist/context/transaction.mjs`, `dist/utils/url.mjs`, `dist/db/adapter/factory.mjs`, `dist/types/init-options.d.mts`
   - `@better-auth/drizzle-adapter@1.7.6` : `dist/index.mjs`
2. **Doc officielle** : <https://www.better-auth.com/docs/plugins/admin>, lue le 2026-11-04. Elle concorde avec le code 1.7.6 sur tous les points vérifiés ci-dessous, sauf mention contraire.
3. **Ce repo** : `packages/core/src/auth/create-auth-instance.ts`, `packages/core/src/auth/auth.service.ts`, `packages/core/src/auth/auth-secondary-storage.ts`, `apps/api/src/auth/{admin.guard,session.guard,admin-2fa.spec}.ts`, `apps/api/src/admin/admin.controller.ts`, `apps/api/src/main.ts`, `packages/db/src/schema/auth.ts`, `apps/mobile/StravaClone/Features/Auth/Infrastructure/APIAuthRepository.swift`, `apps/mobile/StravaClone/Core/Network/SessionEndpoint.swift`, ADR-022 §3 et §5, ADR-035 §3.

Les points marqués **(déduit)** viennent d'une lecture du code, sans exécution.

## 1. Ce que le plugin installe

`admin()` est déjà activé sans option dans `create-auth-instance.ts`. Il apporte (`dist/plugins/admin/admin.mjs`) :

- **15 endpoints**, tous montés sous `/api/auth/admin/*` par `toNodeHandler` (`apps/api/src/main.ts`) et appelables côté serveur via `auth.api.<nom>` :

| Méthode serveur | Route HTTP | Permission requise |
|---|---|---|
| `listUsers` | `GET /admin/list-users` | `user:list` |
| `getUser` | `GET /admin/get-user` | `user:get` |
| `createUser` | `POST /admin/create-user` | `user:create` |
| `adminUpdateUser` | `POST /admin/update-user` | `user:update` (+ `set-role`, `ban`, `set-email` selon les champs) |
| `setRole` | `POST /admin/set-role` | `user:set-role` |
| `banUser` / `unbanUser` | `POST /admin/ban-user`, `/admin/unban-user` | `user:ban` |
| `listUserSessions` | `POST /admin/list-user-sessions` | `session:list` |
| `revokeUserSession` / `revokeUserSessions` | `POST /admin/revoke-user-session(s)` | `session:revoke` |
| `removeUser` | `POST /admin/remove-user` | `user:delete` |
| `setUserPassword` | `POST /admin/set-user-password` | `user:set-password` |
| `impersonateUser` / `stopImpersonating` | `POST /admin/impersonate-user`, `/admin/stop-impersonating` | `user:impersonate` |
| `userHasPermission` | `POST /admin/has-permission` | — |

- **Deux hooks de base de données** (`init()`) : `user.create.before` pose `role: "user"` par défaut ; `session.create.before` refuse la création de session d'un utilisateur banni (voir §3).
- **Un hook `after`** sur `/list-sessions` qui masque à l'utilisateur les sessions d'impersonation.
- **Ses codes d'erreur** (`ADMIN_ERROR_CODES`, `dist/plugins/admin/error-codes.mjs`), dont `BANNED_USER`, `YOU_CANNOT_BAN_YOURSELF`, `YOU_CANNOT_REMOVE_YOURSELF`.

### Contrôle d'accès par défaut

Chaque endpoint (sauf `has-permission`) passe par `adminMiddleware`, qui relit la session de façon « authoritative » (`getAuthoritativeSessionFromCtx`, cache cookie ignoré) et répond `401` sans session. Puis `hasPermission` (`has-permission.mjs`) accepte si :

- l'id de l'appelant est dans `adminUserIds` (option, non utilisée chez nous), **ou**
- un des rôles de `user.role` (séparés par des virgules) a la permission dans `roles` (par défaut `defaultRoles`).

Rôles par défaut (`access/statement.mjs`) : `admin` a **toutes** les permissions `user:*` sauf `impersonate-admins`, et `session:list|revoke|delete` ; `user` n'a rien. Le plugin **ne vérifie ni la 2FA ni la façon dont la session a été ouverte**.

## 2. Méthodes demandées par le ticket

### `listUsers` (recherche, tri, pagination)

Paramètres de requête (`listUsersQuerySchema`, `routes.mjs`) :

- **Recherche** : `searchValue`, `searchField` = `email` (défaut) ou `name`, `searchOperator` = `contains` (défaut), `starts_with`, `ends_with`. Une seule recherche à la fois : pas de « email OU nom ».
- **Filtre** : `filterField` (défaut `email`, n'importe quel champ), `filterValue`, `filterOperator` (`eq` par défaut, et `ne`, `lt`, `lte`, `gt`, `gte`, `in`, `not_in`, `contains`, `starts_with`, `ends_with`). Un seul filtre ; il est combiné en ET avec la recherche.
- **Tri** : `sortBy` (n'importe quel champ), `sortDirection` = `asc` (défaut) ou `desc`.
- **Pagination** : `limit` / `offset` (pagination par décalage). Sans `limit`, l'adaptateur plafonne à **100** (`defaultFindManyLimit ?? 100`, `@better-auth/core` `db/adapter/factory.mjs` ; la doc dit aussi « defaults to 100 »).
- **Réponse** : `{ users, total, limit, offset }`, `total` comptant après recherche et filtre (`countTotalUsers`).

Limites constatées dans le code :

- ⚠️ **Recherche sensible à la casse** sur Postgres : le plugin ne passe pas `mode: "insensitive"`, donc l'adaptateur Drizzle génère un `LIKE`, pas un `ILIKE` (`@better-auth/drizzle-adapter` `dist/index.mjs`, branche `contains`). Chercher « dupont » ne trouve pas « Dupont ».
- ⚠️ **Erreurs avalées** : tout le corps est dans un `try { … } catch { return { users: [], total: 0 } }`. Un `sortBy` inconnu renvoie une liste vide, sans erreur.
- Ne lit que la table Better Auth `user` (champs `id`, `name`, `email`, `emailVerified`, `image`, `role`, `banned`, `banReason`, `banExpires`, `twoFactorEnabled`, dates). Rien du profil (`users`, ADR-036), des Activités ou de l'abonnement.

### `banUser` / `unbanUser`

- Corps : `{ userId, banReason?, banExpiresIn? }`. `banExpiresIn` est en **secondes** ; absent, on prend `defaultBanExpiresIn`, sinon le ban est **définitif** (`banExpires: null`). `banReason` absent : `defaultBanReason`, sinon `"No reason"`.
- Effets, dans l'ordre (`routes.mjs`, `banUser`) : vérifie la permission, `404` si l'utilisateur n'existe pas, `400 YOU_CANNOT_BAN_YOURSELF` si c'est soi-même, met `banned: true` + motif + échéance, puis **`deleteUserSessions(userId)`**.
- `unbanUser` remet `banned: false`, `banReason: null`, `banExpires: null`. Il ne recrée aucune session.
- Un ban expiré n'est levé **qu'à la prochaine création de session** : le hook `session.create.before` voit `banExpires < now`, remet les trois champs à zéro et laisse passer (`admin.mjs` l. 36-43). Aucune tâche planifiée ne le fait.

### `revokeUserSessions`, `setRole`, `removeUser`

- `revokeUserSessions({ userId })` → `deleteUserSessions(userId)`, réponse `{ success: true }`. `revokeUserSession({ sessionToken })` en révoque une seule.
- `setRole({ userId, role })` : `role` est une chaîne ou un tableau (stocké joint par des virgules). La valeur n'est validée contre `roles` **que si l'option `roles` est fournie** ; chez nous, c'est l'enum Postgres `user_role` (`user` | `admin`) qui refusera toute autre valeur, en erreur SQL.
- `removeUser({ userId })` : `400 YOU_CANNOT_REMOVE_YOURSELF`, puis supprime sessions, comptes (`account`) et la ligne `user` (« Hard deletes a user from the database », doc). Chez nous, les tables métier référencent `user.id` avec `onDelete: "cascade"` (`activities`, `engagement`, `social`, `segments`, `itineraries`, `subscriptions`…), donc Postgres efface tout le reste. **(déduit)** Les objets S3 des médias (ADR-037) ne sont pas concernés par la cascade.

## 3. Effet d'un bannissement sur les sessions, y compris le `bearer` iOS

### Les sessions vivent dans Redis, pas dans Postgres

Fait central pour comprendre la révocation : avec `secondaryStorage` configuré (Redis, ADR-022 §4) et **sans** `session.storeSessionInDatabase`, Better Auth n'écrit **pas** les sessions dans la table `session` :

- `createSession` appelle `createWithHooks(…, { fn: mirrorSessionToSecondaryStorage, executeMainFn: storeInDb })` ; `storeInDb` vaut `undefined`, donc l'insertion SQL n'a pas lieu (`with-hooks.mjs` : `if (!customCreateFn || customCreateFn.executeMainFn)`). La session est stockée sous la clé Redis `<token>` (avec une copie de l'utilisateur), et listée sous `active-sessions-<userId>`.
- `findSession(token)` lit Redis ; absent de Redis et sans `storeSessionInDatabase`, il renvoie `null` (`internal-adapter.mjs` l. 322-324).
- `create-auth-instance.ts` ne définit ni `storeSessionInDatabase` ni `cookieCache` (vérifié par recherche dans `packages/core/src` et `apps/api/src`).

**(déduit)** La table Postgres `session` (et ses colonnes `impersonatedBy`, `authMethod`) reste donc vide en production ; `authMethod` n'existe que dans la copie Redis, ce qui suffit à `AdminGuard`.

### Coupure immédiate

`deleteUserSessions(userId)` (appelé par `banUser`, `revokeUserSessions`, `removeUser`, et `adminUpdateUser` avec `banned: true`) supprime chaque clé `<token>` listée dans `active-sessions-<userId>`, puis la liste elle-même (`deleteCachedUserSessions`). Hors transaction, `queueAfterTransactionHook` exécute la suppression tout de suite (`@better-auth/core` `context/transaction.mjs` l. 105-113).

Le jeton `bearer` de l'app iOS **est** le jeton de session : le plugin `bearer` le recopie en cookie de session avant chaque endpoint (`plugins/bearer/index.mjs`). La requête suivante de l'iPhone ne trouve donc plus de session : **coupure immédiate**, pas à l'expiration. Aucun `cookieCache` n'est actif, donc pas de fenêtre de grâce non plus côté backoffice.

⚠️ Le contrôle `banned` n'existe **qu'à la création de session** : `grep banned` dans tout `dist/` ne sort que les fichiers du plugin `admin`, et `getSession` ne lit pas ce champ. Poser `banned: true` autrement que par le plugin (SQL direct, `internalAdapter.updateUser`) **laisse vivre les sessions existantes** jusqu'à leur expiration (7 jours par défaut, prolongés à chaque usage). Il faut toujours passer par `banUser` ou appeler `deleteUserSessions` soi-même.

### Ce que reçoit l'app iOS

- **Sur une route `/v1/*`** : `SessionGuard` lève `UnauthorizedException`, donc un `401` **sans code spécifique**. L'app le traite comme une session expirée : `APISessionRefresher` appelle `GET /api/auth/get-session`, qui répond `null`, puis l'utilisateur est renvoyé vers la connexion (`SessionEndpoint.swift`, `APIAuthRepository.currentUser` → `.notSignedIn`). L'app ne peut pas distinguer « banni » de « déconnecté » à ce stade.
- **À la reconnexion** : `403` avec `{ "code": "BANNED_USER", "message": <bannedUserMessage> }` (`APIError.from("FORBIDDEN", { message, code: "BANNED_USER" })`, `admin.mjs` l. 47-50). `APIAuthRepository.mapError` ne connaît pas ce code et affiche le `message` du serveur (`AuthError.server(message:)`). Message par défaut, en anglais : « You have been banned from this application. Please contact support if you believe this is an error. » L'option `bannedUserMessage` accepte une chaîne ou une fonction `(user) => string` (`types.d.mts`), donc un texte français incluant `banReason` est possible.

### Toutes les méthodes de connexion sont bloquées

Toutes créent leur session par `internalAdapter.createSession`, qui déclenche le hook du plugin :

- **Code e-mail** (`/sign-in/email-otp`) : `plugins/email-otp/routes.mjs` l. 334, 422, 438. ⚠️ L'envoi du code (`/email-otp/send-verification-otp`) ne vérifie pas le ban : un banni **reçoit** encore le code par e-mail, et c'est la validation qui renvoie `403 BANNED_USER`.
- **Google par `idToken`** (iOS, `/sign-in/social`) : `handleOAuthUserInfo` → `createSession` (`oauth2/link-account.mjs` l. 322), sans `try/catch` autour dans `sign-in.mjs` : même `403 BANNED_USER` en JSON.
- **Google par redirection** (navigateur) : `callback.mjs` l. 191-192 attrape l'erreur et redirige vers l'URL d'erreur avec `?error=BANNED_USER`.
- **Mot de passe (+ 2FA)** du backoffice (`sign-in.mjs` l. 352) : même hook.

Exception : une session créée **hors endpoint** (`internalAdapter.createSession` appelé directement, comme dans `admin-2fa.spec.ts`) n'a pas de contexte, et le hook sort tout de suite (`if (!ctx) return;`).

## 4. Colonnes et activation partielle

### Colonnes

Le schéma du plugin (`dist/plugins/admin/schema.mjs`) : `user.role` (string), `user.banned` (boolean, défaut `false`), `user.banReason` (string), `user.banExpires` (date), `session.impersonatedBy` (string), toutes en `input: false`. Elles existent déjà dans `packages/db/src/schema/auth.ts` (`role` est un enum Postgres `user_role`, `impersonatedBy` un `uuid`). **Aucune migration n'est nécessaire.**

### Activer seulement certaines capacités

Le plugin n'a **pas d'option pour désactiver un endpoint** : ses options sont `defaultRole`, `adminRoles`, `defaultBanReason`, `defaultBanExpiresIn`, `impersonationSessionDuration`, `schema`, `ac`, `roles`, `adminUserIds`, `bannedUserMessage`, `allowImpersonatingAdmins` (`types.d.mts`). Les 15 endpoints sont toujours montés. Trois leviers existent :

1. **`roles` + `ac` personnalisés** : un rôle `admin` construit avec `createAccessControl(defaultStatements).newRole({ user: [...sans "impersonate"...], session: [...] })` retire la permission partout, en HTTP comme via `auth.api`. La doc prévient que des rôles personnalisés **remplacent** les permissions par défaut.
2. **`disabledPaths`** (option racine de `betterAuth`, `init-options.d.mts` l. 1528) : le routeur répond `404` pour les chemins listés (`api/index.mjs` l. 166-168). La comparaison est **exacte** (`includes`) sur le chemin sans `/api/auth` (`normalizePathname`), donc il faut lister chaque route (`/admin/ban-user`, `/admin/impersonate-user`…), pas un préfixe. Ce filtre vit dans `onRequest` du routeur HTTP : **(déduit)** il ne bloque pas les appels serveur `auth.api.*`.
3. **Un hook `hooks.before`** avec un `matcher` sur `ctx.path.startsWith("/admin/")` qui lève une erreur pour les requêtes HTTP.

ADR-022 §3 dit que le backoffice « n'active pas » `impersonateUser`. ⚠️ Dans le code actuel, rien ne le désactive : `POST /api/auth/admin/impersonate-user` répond à tout compte `role = "admin"`.

## 5. Articulation avec `AdminGuard`

### Les deux contrôles ne se recouvrent qu'en partie

| | `AdminGuard` (`/v1/admin/*`) | Plugin (`/api/auth/admin/*`) |
|---|---|---|
| Rôle | `role === "admin"` | `role` contient un rôle autorisé dans `roles` |
| 2FA activée | exigée (`ADMIN_2FA_REQUIRED`) | non vérifiée |
| Session forte `password_2fa` (ADR-035 §3) | exigée (`ADMIN_STRONG_SESSION_REQUIRED`) | non vérifiée |
| Permissions fines | non | oui (`user:ban`, `session:revoke`…) |
| Garde-fous | — | pas d'auto-ban ni d'auto-suppression |

Ils ne se contredisent pas : quand `AdminGuard` laisse passer, le plugin laisse passer aussi (même rôle `admin`, et le rôle par défaut a toutes les permissions demandées sauf `impersonate-admins`).

### ⚠️ Les routes du plugin contournent la session forte **(déduit)**

Les endpoints `/api/auth/admin/*` sont exposés aujourd'hui et ne regardent que le rôle. Un admin connecté sur l'iPhone par code e-mail ou Google (session « faible », refusée par `AdminGuard`) peut donc, avec son jeton `bearer`, appeler directement `ban-user`, `set-role`, `remove-user`, `set-user-password` ou `impersonate-user`. Le contrôle d'origine ne l'en empêche pas : il ne s'applique qu'aux requêtes qui portent un en-tête `cookie` (`origin-check.mjs` l. 101-108), et l'app iOS n'en envoie pas (#135). Cela contredit l'intention d'ADR-035 §3 (« seule une session mot de passe + 2FA porte les droits admin »). Non vérifié par un test d'exécution.

### Appeler le plugin depuis nos endpoints `/v1/admin/*`

Oui, c'est possible et c'est le schéma déjà en place pour `getSession` :

- **Via `auth.api.banUser({ headers, body })`** (et `listUsers`, `revokeUserSessions`, `setRole`, `removeUser`) en transmettant les en-têtes de la requête entrante (`fromNodeHeaders(request.headers)`, comme `SessionGuard`). La doc le montre avec `headers: await headers()` (« This endpoint requires session cookies »). Le plugin relit la session de l'admin (cookie ou bearer) et refait son contrôle de rôle, redondant mais cohérent après `AdminGuard`. On garde ses garde-fous (pas d'auto-ban, `404` si l'utilisateur n'existe pas) et la révocation des sessions. Ses erreurs sont des `APIError` (statut + `{ code, message }`) à traduire dans notre format d'erreur.
- **Via `internalAdapter`** (`(await auth.$context).internalAdapter.updateUser(...)` puis `deleteUserSessions(...)`), comme le fait déjà `AuthService.markEmailUnverified` : aucune session admin requise, mais on réécrit soi-même les garde-fous et on risque d'oublier la révocation (voir §3).

Combiné à `disabledPaths` sur toutes les routes `/admin/*`, le premier choix ferme la surface HTTP du plugin tout en gardant ses méthodes côté serveur.

## Questions ouvertes (pour la carte, pas tranchées ici)

- Fermer `/api/auth/admin/*` en HTTP (`disabledPaths` ou hook `before`) et ne passer que par `/v1/admin/*` ?
- Retirer `impersonate` des permissions (rôles personnalisés), conformément à ADR-022 §3 ?
- Recherche insensible à la casse et sur email OU nom : `listUsers` ne le permet pas ; requête maison dans un repository (`AuthUserRepository`) ou acceptation de la limite ?
- Message `bannedUserMessage` en français, et code `BANNED_USER` à reconnaître côté iOS pour un écran dédié ?
- `removeUser` et les fichiers S3 (ADR-037) : qui les nettoie ?
