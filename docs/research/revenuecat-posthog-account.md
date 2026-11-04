# Recherche : RevenueCat et PostHog pour un compte (état, Premium promotionnel, suppression)

- **Ticket** : [#193 RevenueCat et PostHog pour un compte : état, Premium promotionnel, suppression](https://github.com/echimine/clone-strava/issues/193) (carte wayfinder [#190](https://github.com/echimine/clone-strava/issues/190) « Backoffice Nervo »)
- **Date** : 2026-11-04
- **Question** : que permettent les API RevenueCat (REST v1 et v2) et PostHog (Cloud EU) pour un compte donné : lire l'état d'abonnement, accorder et retirer un Premium promotionnel, supprimer l'abonné ; supprimer une personne et ses événements dans PostHog, la retrouver par `distinct_id`, savoir ce qui reste ; et quelles contraintes RGPD encadrent la suppression de compte ?
- **Sources** : documentation officielle RevenueCat (`revenuecat.com/docs`, références API v1 et v2, lues directement et via context7), blog d'ingénierie RevenueCat ; documentation officielle PostHog (`posthog.com/docs` : API, Persons API, suppression de données, RGPD, SDK iOS) ; page Apple « Offering account deletion in your app » ; RGPD (texte publié par la CNIL). Lu le **2026-11-04**. Code du dépôt à `2c0808d`.
- **Non vérifié** : aucun appel n'a été fait aux API RevenueCat ou PostHog (lecture de doc uniquement). Les points marqués ⚠️ ne sont pas documentés explicitement et sont à confirmer par un essai en sandbox.

Conventions : **Fait** = ce que dit une source, avec son lien. **Recommandation** = mon avis pour Nervo, à trancher dans la carte.

---

## TL;DR

1. **Lire l'état** : v1 `GET /v1/subscribers/{app_user_id}` renvoie entitlements, abonnements (`store`, `period_type`, `expires_date`, `grace_period_expires_date`, `unsubscribe_detected_at`, `billing_issues_detected_at`, `is_sandbox`) et `management_url`, mais **crée le client s'il n'existe pas** (`201`). v2 sépare `GET …/customers/{id}` (entitlements actifs) et `GET …/customers/{id}/subscriptions` (`status`, `gives_access`, `auto_renewal_status`, `store`).
2. **Premium promotionnel** : v1 `POST /v1/subscribers/{id}/entitlements/premium/promotional` avec `end_time_ms` (le paramètre `duration` est déprécié) ; retrait par `POST …/revoke_promotionals`. En v2 : `actions/grant_entitlement` (`entitlement_id` + `expires_at`) et `actions/revoke_granted_entitlement`. Un Premium promotionnel **ne touche jamais l'abonnement App Store** : il s'ajoute à lui, sans annulation, débit ni remboursement.
3. **Webhooks du promotionnel** : l'octroi arrive comme `NON_RENEWING_PURCHASE` de production, avec `store` et `period_type` à `PROMOTIONAL`. Le retrait ou la fin arrivent comme `CANCELLATION` (`DEVELOPER_INITIATED`) ou `EXPIRATION`. Notre schéma (`store` = `app_store` seul, `period_type` = `trial|intro|normal`) **ne sait pas stocker** un promotionnel.
4. **Suppression RevenueCat** : `DELETE /v1/subscribers/{id}` ou v2 `DELETE …/customers/{id}` met la suppression **en file, de façon asynchrone** ; un `404` confirme la fin. RevenueCat la juge **suffisante pour une demande d'effacement RGPD**. Elle **n'annule pas l'abonnement Apple**, et le développeur ne peut pas l'annuler à la place de l'athlète. Il faut aussi appeler `logOut()` dans le SDK, sinon le client est recréé.
5. **Clés et limites RevenueCat** : la suppression et l'octroi demandent une **clé secrète** (`sk_…`, côté serveur seulement). v2 limite le domaine *Customer Information* à **480 requêtes/min**, avec `Retry-After` sur `429`. La doc officielle ne publie aucune limite pour v1.
6. **Suppression PostHog** : `DELETE /api/projects/{project_id}/persons/{uuid}/?delete_events=true&delete_recordings=true` ou `POST …/persons/bulk_delete` avec `distinct_ids` (1 000 max), clé personnelle avec le scope `person:write`, sur `https://eu.posthog.com`. La personne disparaît vite, mais **les événements sont effacés par lots le week-end**, avec une date limite deux jours avant le lot. Le suivi passe par `GET …/persons/deletion_status`.
7. **Retrouver la personne** : `GET …/persons/?distinct_id={userId}` (scope `person:read`). Le `distinct_id` d'un compte est **son `user.id`**, côté app après `identify` comme côté serveur. Les événements anonymes d'avant connexion sont rattachés par `identify`. Ceux d'après la déconnexion (`reset()`) portent un nouvel identifiant anonyme, sans lien avec le compte.
8. **Ce qui existe vraiment aujourd'hui** : le SDK RevenueCat est lié à l'app mais **jamais importé** (`UnwiredSubscriptionService`), donc aucun client RevenueCat n'existe encore pour nos comptes. La synchro serveur (`SyncSubscriptionUseCase`) lève `NotImplementedException`. PostHog reçoit en revanche des événements serveur pour **tous** les comptes, consentement ou non (écart accepté par ADR-035 §8, [#115](https://github.com/echimine/clone-strava/issues/115)).
9. **RGPD** : réponse « dans les meilleurs délais et en tout état de cause dans un délai d'un mois », prolongeable de deux mois (art. 12.3). Effacement « dans les meilleurs délais » (art. 17.1). Chaque destinataire des données doit être informé de l'effacement (art. 19), ce qui correspond chez nous à RevenueCat et PostHog. Apple accepte une suppression différée si l'app indique le délai et confirme la fin.

---

## 1. Ce que fait notre code aujourd'hui

| Point | Constat | Fichier |
|---|---|---|
| Identité RevenueCat | ADR-014 prévoit `Purchases.logIn(userId)`, mais aucun fichier Swift n'importe `RevenueCat` : le paquet `purchases-ios` 5.91.0 est lié et `RevenueCatAPIKey` est dans l'`Info.plist`, sans être utilisés. Le Paywall passe par `UnwiredSubscriptionService` (ADR-035 §6). | `apps/mobile/project.yml`, `Features/Paywall/Infrastructure/UnwiredSubscriptionService.swift` |
| Webhook | `POST /v1/webhooks/revenuecat` vérifie le secret puis appelle `handleWebhook(event.id, event.app_user_id)`. | `apps/api/src/webhooks/revenuecat.controller.ts` |
| Synchro | Le processeur `sync-subscription` (concurrence 10) appelle `SubscriptionsService.sync`, dont les deux cas d'usage lèvent encore `NotImplementedException`. | `apps/worker/src/processors/subscriptions/`, `packages/core/src/subscriptions/use-cases/` |
| Clé serveur | `REVENUECAT_API_KEY` (worker uniquement). Le type de clé (v1 secrète ou v2 avec permissions) n'est fixé nulle part. | `packages/contracts/src/config/env.ts` |
| Table d'état | `subscriptions.user_subscription` : PK `(user_id, entitlement_id)`, `store` enum `app_store` **seul**, `period_type` enum `trial|intro|normal`, `environment` `sandbox|production`, dates d'expiration, de grâce, de problème de facturation et de désabonnement. `revenuecat_event.user_id` référence `user` (`on delete cascade`). | `packages/db/src/schema/subscriptions.ts` |
| Règle Premium | Actif et (`grace_period_expires_at` ou `expires_at`) dans le futur ; actif sans date d'expiration = Premium. | `packages/core/src/subscriptions/domain/is-premium.ts` |
| PostHog app | `posthog-ios` 3.82.0, hôte `https://eu.i.posthog.com`. Le SDK démarre en opt-out tant que la Mesure d'audience n'est pas acceptée ; replay, autocapture d'écrans et d'éléments, et sondages sont désactivés. `identify(user.id)` à la connexion et à la restauration de session, `reset()` à la déconnexion. `personProfiles` n'est pas réglé : c'est donc la valeur par défaut, `.identifiedOnly`. | `Core/Analytics/PostHogAnalyticsClient.swift`, `Features/Auth/Presentation/AuthStore.swift`, `Core/Analytics/MeasurementConsentStore.swift` |
| Événements « sans identifiant » | Les événements Médias et Avatar (ADR-037 §13) ne portent ni `mediaId` ni `activityId`, mais ils partent bien sous le `distinct_id` de la session : le `user.id` après `identify`. | `docs/adr/ADR-037-media-avatar-and-gallery.md` §13 |
| PostHog serveur | `posthog-node` 5.53.0, `capture({ distinctId: userId, … })` pour `user_signed_up`, `activity_*`, `itinerary_*`, `onboarding_answers_received`. Aucun `$process_person_profile: false` : ces événements créent ou mettent à jour une personne. Envoyés **sans tenir compte du consentement** (ADR-035 §8). | `packages/core/src/analytics/analytics.service.ts` |
| Clé PostHog serveur | `POSTHOG_API_KEY` est la clé **de projet** (ingestion). Elle ne permet pas d'appeler l'API privée (lecture et suppression des personnes). | `packages/contracts/src/config/env.ts` |
| Suppression de compte | Prévue mais non conçue. ADR-037 §11 : le futur job efface `activities/{userId}/`, `imports/{userId}/` et `avatars/{userId}/` après la cascade en base ; « RevenueCat, PostHog et UI » restent à cette future tâche. | `docs/adr/ADR-037-media-avatar-and-gallery.md` |

---

## 2. RevenueCat

### 2.1 Clés et versions

| Fait | Source |
|---|---|
| Deux types de clés. Les clés **publiques** (« SDK API keys ») servent à configurer le SDK pour des « non-potent changes ». Les clés **secrètes**, préfixées `sk_`, se gardent sur nos serveurs et *« can perform restricted API requests such as deleting subscribers and granting entitlements »*. Elles valent pour tout le projet. | [Authentication](https://www.revenuecat.com/docs/projects/authentication) |
| v1 : *« refunds, promotional entitlements, and other sensitive actions that can only be done via a Secret API key »*. | [API v1](https://www.revenuecat.com/docs/api-v1) |
| v2 : `Authorization: Bearer sk_…`, avec des permissions choisies à la création de la clé. *« API v1 keys will not work with REST API v2 »*. | [API v2](https://www.revenuecat.com/docs/api-v2) |
| La doc v2 ne déclare pas v1 dépréciée et ne donne aucune date de fin. | [API v2](https://www.revenuecat.com/docs/api-v2) |

### 2.2 Lire l'état d'un abonné

| Fait | Source |
|---|---|
| **v1** `GET /v1/subscribers/{app_user_id}` : *« Gets the latest Customer Info … or creates a new customer if it doesn't exist »* (`200` s'il existe, `201` s'il vient d'être créé). Le header `X-Platform` est à omettre pour une lecture informative. | [API v1 Customers](https://www.revenuecat.com/docs/api-v1/customers) |
| Réponse v1 : `subscriber.entitlements` (dont les expirés) → `expires_date`, `grace_period_expires_date`, `product_identifier`, `purchase_date`. `subscriber.subscriptions[product]` → `store` (`app_store`, `promotional`…), `period_type`, `expires_date`, `grace_period_expires_date`, `unsubscribe_detected_at`, `billing_issues_detected_at`, `refunded_at`, `is_sandbox`, `ownership_type`. Plus `management_url` (*« If the Customer has an active App Store subscription, this will point to the App Store »*), `first_seen`, `last_seen` et `subscriber_attributes` (avec une clé secrète seulement). | [API v1 Customers](https://www.revenuecat.com/docs/api-v1/customers) |
| Un promotionnel apparaît dans `subscriptions` sous une clé `rc_promo_…`, avec `"store": "promotional"` et `"is_sandbox": false`. | [API v1 Customers](https://www.revenuecat.com/docs/api-v1/customers) (exemple de réponse) |
| **v2** `GET /v2/projects/{project_id}/customers/{customer_id}` (permission `customer_information:customers:read`) renvoie `active_entitlements` (`entitlement_id`, `expires_at`), `first_seen_at`, `last_seen_at` et l'`experiment`. La doc de suppression utilise son `404` pour dire « le client n'existe pas » : rien n'indique qu'elle crée le client. | [API v2 Customer](https://www.revenuecat.com/docs/api-v2/customer), [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile) |
| **v2** `GET …/customers/{customer_id}/subscriptions` : `status` (`trialing`, `active`, `expired`, `in_grace_period`, `in_billing_retry`, `paused`, `unknown`, `incomplete`), `gives_access`, `auto_renewal_status` (`will_renew`, `will_not_renew`…), `current_period_ends_at`, `store` (dont `promotional`), `environment`, `entitlements` (avec le `lookup_key`, par exemple `premium`) et `management_url`. *« To determine whether or not a subscription currently provides access … use the gives_access field »*. | [API v2 Customer resources](https://www.revenuecat.com/docs/api-v2/customer/resources), [API v2 Subscription](https://www.revenuecat.com/docs/api-v2/subscription) |

### 2.3 Accorder et retirer un Premium promotionnel

| Fait | Source |
|---|---|
| **v1** `POST /v1/subscribers/{app_user_id}/entitlements/{entitlement_identifier}/promotional` avec `end_time_ms` (epoch en ms). `duration` (`daily`, `three_day`, `weekly`, `two_week`, `monthly`, `two_month`, `three_month`, `six_month`, `yearly`, `lifetime`) et `start_time_ms` sont **dépréciés**. *« The entitlement will always be granted immediately. »* *« Does not override or defer a store transaction, applied simultaneously. »* Répond `201` avec le Customer Info. | [API v1 Entitlements](https://www.revenuecat.com/docs/api-v1/entitlements) |
| **v1** `POST /v1/subscribers/{app_user_id}/entitlements/{entitlement_identifier}/revoke_promotionals` : *« Revokes all granted entitlements for a given entitlement identifier and App User ID. »* | [API v1 Entitlements](https://www.revenuecat.com/docs/api-v1/entitlements) |
| **v2** `POST …/customers/{customer_id}/actions/grant_entitlement` avec `{ entitlement_id, expires_at }`. `entitlement_id` est l'**ID RevenueCat** de l'entitlement (`entl…`), pas son `lookup_key`. Une demande dont l'`expires_at` tombe à moins de deux heures d'un octroi existant est ignorée comme doublon. Pour **allonger**, on accorde de nouveau avec une date plus lointaine (les deux octrois coexistent). Pour **raccourcir**, on retire puis on accorde de nouveau. | [API v2 Customer](https://www.revenuecat.com/docs/api-v2/customer), [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile) |
| **v2** `POST …/actions/revoke_granted_entitlement` `{ entitlement_id }` : *« Revokes all active promotional grants of this entitlement. Associated promotional subscriptions are expired and access ends immediately. »* | [API v2 Customer](https://www.revenuecat.com/docs/api-v2/customer) |
| Les octrois *« work independently of the App Store … »* et *« never cancel a user's subscription, charge a user, issue a refund, or convert to a paid subscription »*. Ils valent en sandbox comme en production, mais leurs transactions sont toujours de production. Côté app, il faut rafraîchir `CustomerInfo` pour les voir. | [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile) |
| Les endpoints d'extension d'un abonnement payant (Apple extend, v2 `extend`) ne s'appliquent pas aux octrois. | [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile) |
| Webhooks : un octroi est envoyé comme `NON_RENEWING_PURCHASE` de production, *« with their store and period type set to PROMOTIONAL »*. Pour le magasin « Promo », seuls `NON_RENEWING_PURCHASE`, `CANCELLATION` (raison `DEVELOPER_INITIATED` uniquement), `EXPIRATION` et `EXPERIMENT_ENROLLMENT` sont émis. `app_id` est absent quand `store` vaut `PROMOTIONAL`. | [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile), [Webhook event types](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields) |
| ⚠️ Accorder à un `app_user_id` jamais vu crée-t-il le client ? La doc ne le dit pas. C'est probable en v1, qui prend un `app_user_id` libre, mais c'est à vérifier en sandbox. | — |

### 2.4 Supprimer un abonné

| Fait | Source |
|---|---|
| **v1** `DELETE /v1/subscribers/{app_user_id}` : *« Permanently deletes a customer. Deletion is queued asynchronously. »* Après un `200`, *« treat a 404 as confirmation that the customer no longer exists »*. | [API v1 Customers](https://www.revenuecat.com/docs/api-v1/customers) |
| **v2** `DELETE /v2/projects/{project_id}/customers/{customer_id}` (permission `customer_information:customers:read_write`) : *« customer deletion was queued and will be processed asynchronously »*. On confirme ensuite par un `404` sur `GET` du client. | [API v2 Customer](https://www.revenuecat.com/docs/api-v2/customer), [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile) |
| La suppression efface toutes les données du client et *« is sufficient for GDPR erasure requests »*. | [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile) |
| Elle **n'annule pas** les abonnements des magasins. Google Play peut s'annuler par l'API avant la suppression. **Un abonnement Apple ne peut pas être annulé par le développeur.** | [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile) |
| *« deleting a customer in RevenueCat does not delete or change their subscription with Apple or Google in any way »*. Il faut aussi *« make sure that the customer is also logged out through the RevenueCat SDK »* ; sinon, si l'athlète continue d'utiliser l'app avec un abonnement actif, il est recréé comme client anonyme (blog de mai 2022, mis à jour en juin 2024). | [Account deletion rules on the App Store](https://www.revenuecat.com/blog/engineering/app-store-account-deletion) |
| Aucun webhook n'est émis à la suppression d'un client. | [Webhook event types](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields) |

### 2.5 Limites de débit

| Fait | Source |
|---|---|
| v2 : limite par domaine, partagée par tous les endpoints du domaine. *Customer Information* : **480 req/min** (lecture, octroi, retrait, suppression d'un client, abonnements). Elle se compte par clé d'app ou par développeur. Les en-têtes `RevenueCat-Rate-Limit-Current-Usage` et `-Current-Limit` indiquent l'usage ; un `429` porte `Retry-After` et `backoff_ms`. | [API v2](https://www.revenuecat.com/docs/api-v2) |
| v1 : **aucune limite publiée** dans la doc officielle. Des réponses anciennes du staff sur le forum conseillent « around 1 request per second » (source secondaire). Un `429` de code 7638 signale une autre requête en cours sur la même ressource : on réessaie quelques secondes plus tard. | [Forum RevenueCat, limites v1](https://community.revenuecat.com/general-questions-7/what-are-the-current-rate-limits-on-the-rest-api-4946), [429 « another request in flight »](https://community.revenuecat.com/featured-articles-55/how-to-solve-429-there-is-another-request-in-flight-trying-to-perform-the-same-action-2070) |

---

## 3. PostHog (Cloud EU)

### 3.1 Domaines, clés et limites

| Fait | Source |
|---|---|
| Sur EU Cloud : `https://eu.i.posthog.com` pour les endpoints publics (ingestion), `https://eu.posthog.com` pour l'API privée. | [API overview](https://posthog.com/docs/api) |
| L'API privée exige une **clé personnelle** avec des scopes : `person:read` pour lister les personnes et l'état des suppressions, `person:write` pour supprimer. | [Persons API](https://posthog.com/docs/api/persons) |
| Limites, comptées **par clé personnelle** : endpoints analytiques (calcul d'insights, *« retrieving persons »*, enregistrements) **240/min et 1 200/h** ; autres CRUD **480/min et 4 800/h** ; endpoint `query` 2 400/h. L'ingestion (`/e`, `/i/v0/e`) n'est pas limitée. | [API rate limiting](https://posthog.com/docs/api) |

### 3.2 Retrouver une personne

| Fait | Source |
|---|---|
| `GET /api/projects/{project_id}/persons/?distinct_id={id}` (ou `email`, `search`) renvoie `uuid`, `distinct_ids[]`, `properties`, `created_at` et `last_seen_at`. | [Persons API](https://posthog.com/docs/api/persons) |
| iOS : `identify` lie *« all previously tracked anonymous events »* à l'utilisateur. `reset()` à la déconnexion *« unlink[s] future events from the user »*. | [iOS usage](https://posthog.com/docs/libraries/ios/usage), [Identify](https://posthog.com/docs/product-analytics/identify) |
| iOS, `personProfiles: .identifiedOnly` (*« recommended, default »*) : les événements anonymes ne créent pas de personne ; les profils ne sont traités qu'après `identify`. | [iOS usage](https://posthog.com/docs/libraries/ios/usage) |
| Les SDK serveur capturent des événements **identifiés par défaut**. Pour un événement anonyme, il faut `$process_person_profile: false`. | [Capture events](https://posthog.com/docs/product-analytics/capture-events) |

**Pour Nervo** : la personne d'un compte a pour `distinct_id` le `user.id` (UUID). Elle existe dès le premier événement serveur (`user_signed_up`), que l'athlète ait consenti ou non. Si l'athlète a consenti sur un téléphone, le `distinct_id` anonyme d'avant connexion s'ajoute à ses `distinct_ids` lors d'`identify`. Les événements envoyés après une déconnexion portent un nouvel identifiant anonyme et ne se rattachent pas au compte.

### 3.3 Supprimer une personne et ses données

| Fait | Source |
|---|---|
| `DELETE /api/projects/{project_id}/persons/{uuid}/?delete_events=true&delete_recordings=true`. `delete_recordings` détruit les enregistrements par *crypto-shredding*, de façon irréversible. | [Data deletion](https://posthog.com/docs/privacy/data-deletion), [Data storage](https://posthog.com/docs/privacy/data-storage) |
| `POST /api/projects/{project_id}/persons/bulk_delete` : `ids` ou `distinct_ids`, **1 000 max par appel**, plus `delete_events`, `delete_recordings` et `keep_person`. *« Only events captured before the request will be deleted. »* Répond `202`. La personne est retirée *« in the background shortly after »* : le signal de succès est `persons_queued_for_deletion`, pas `persons_deleted` (toujours 0). Tout ce qui figure dans `deletion_errors` est à réessayer. | [Persons API](https://posthog.com/docs/api/persons), [Data deletion](https://posthog.com/docs/privacy/data-deletion) |
| *« Event data is cleared asynchronously during non-peak usage times (weekends on PostHog Cloud). »* *« The request cutoff time for each batch deletion is two days before the batch runs »*. Une demande arrivée après la date limite part dans le lot suivant. | [Data deletion](https://posthog.com/docs/privacy/data-deletion) |
| `GET …/persons/deletion_status/?person_uuid=…&status=pending|completed|all` (scope `person:read`) renvoie `status` et `delete_verified_at`. | [Persons API](https://posthog.com/docs/api/persons) |
| *« Once the deletion process is fully processed, PostHog does not retain any data associated with the deleted distinct_id. »* Il faut éviter de réutiliser un `distinct_id` pendant le traitement ; l'outil « Reset deleted person » permet de le réutiliser ensuite. | [Data deletion](https://posthog.com/docs/privacy/data-deletion) |
| *« To answer a right to be forgotten request, delete the person »*. PostHog Cloud EU est hébergé à Francfort ; PostHog y est sous-traitant (DPA, art. 28). La doc RGPD de PostHog ne fixe aucun délai de réponse. | [Data deletion](https://posthog.com/docs/privacy/data-deletion), [GDPR compliance](https://posthog.com/docs/privacy/gdpr-compliance) |
| ⚠️ Les événements anonymes capturés avant `identify` (en `.identifiedOnly`) sont-ils supprimés avec `delete_events=true` ? La doc parle des événements « of the person(s) » sans préciser. C'est probable, puisqu'`identify` les rattache à la personne, mais c'est à vérifier sur un compte de test. | — |

**Délai réel (calcul de notre part)** : la personne disparaît en quelques instants. Les événements sont effacés au lot du week-end si la demande précède la date limite (deux jours avant), sinon au lot suivant : **jusqu'à environ deux semaines**, ce qui reste dans le mois du RGPD. Nervo n'a ni enregistrement de session (replay désactivé) ni propriété personnelle (ADR-015) ; passer `delete_recordings=true` ne coûte rien.

---

## 4. RGPD et règles Apple utiles à la suppression de compte

| Fait | Source |
|---|---|
| Le responsable répond *« dans les meilleurs délais et en tout état de cause dans un délai d'un mois à compter de la réception de la demande »*, délai qui *« peut être prolongé de deux mois, compte tenu de la complexité et du nombre de demandes »* (art. 12.3). | [RGPD chapitre III (CNIL)](https://www.cnil.fr/fr/reglement-europeen-protection-donnees/chapitre3) |
| Droit à l'effacement *« dans les meilleurs délais »*, notamment quand le consentement est retiré ou que les données ne sont plus nécessaires (art. 17.1). | même source |
| Le responsable *« notifie à chaque destinataire auquel les données à caractère personnel ont été communiquées »* tout effacement, sauf impossibilité ou effort disproportionné (art. 19). Pour Nervo, ces destinataires sont RevenueCat et PostHog. | même source |
| Apple : avec un abonnement auto-renouvelable, *« notify them that billing will continue through Apple and ask them to cancel their subscription before continuing »*, via `showManageSubscriptions` ou `https://apps.apple.com/account/subscriptions/`. On peut proposer une suppression programmée à la fin de l'abonnement *« as long as there's also an option to delete the account immediately »*. Une suppression qui prend du temps est acceptée : *« Inform the person how long it will take … and provide a confirmation when the deletion is complete »*. | [Apple, Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/) |
| Journaliser la demande : le RGPD n'impose pas de format. L'obligation de pouvoir *démontrer* la conformité (art. 5.2) justifie de garder une trace minimale (date de la demande, date d'exécution, systèmes traités), sans les données effacées. C'est mon interprétation, pas une règle écrite. | — |

---

## 5. Ce que ça implique pour Nervo (recommandations)

1. **Lire l'état dans notre base, pas dans RevenueCat.** La fiche utilisateur du backoffice lit `user_subscription`, déjà synchronisée par le worker. Un bouton « Resynchroniser » peut mettre `sync-subscription` en file. **Jamais de `GET /v1/subscribers` pour un simple affichage**, puisqu'il crée un client RevenueCat pour un compte qui n'a jamais rien acheté. Si une lecture en direct s'impose, prendre v2 `GET …/customers/{id}` et `…/subscriptions` (un `404` veut dire « pas de client »).
2. **Premium promotionnel = un appel RevenueCat, puis le webhook habituel.** `/v1/admin/users/:id/premium` appelle RevenueCat : v1 `…/entitlements/premium/promotional` avec `end_time_ms`, ou v2 `grant_entitlement` avec l'ID `entl…` à mettre en configuration. Le retrait passe par `revoke_promotionals` ou `revoke_granted_entitlement`. On n'écrit pas `user_subscription` à la main : le webhook (`NON_RENEWING_PURCHASE`, puis `CANCELLATION` ou `EXPIRATION`) déclenche `sync-subscription`, qui relit l'état. Le webhook peut tarder quelques secondes : le backoffice peut aussi mettre la synchro en file juste après l'appel.
3. **Amender le schéma (ADR-017)** : ajouter `promotional` aux enums `subscriptions.store` et `subscriptions.period_type`. Décider aussi comment la synchro fusionne un promotionnel et un achat App Store simultanés, puisque la PK `(user_id, entitlement_id)` n'admet qu'une ligne : par exemple l'entitlement `premium` agrégé (expiration la plus lointaine) plus la source dominante.
4. **Choisir v1 ou v2 et le type de `REVENUECAT_API_KEY`.** v2 a des permissions fines (`customer_information:customers:read_write`), une limite documentée (480/min) et un `GET` sans effet de bord ; v1 identifie l'entitlement par `premium` directement. Dans les deux cas, la clé est **secrète** et réservée au worker et à l'API. Le volume du backoffice (quelques appels par jour) est très loin des limites.
5. **Ordre de la suppression de compte** (un seul service, appelé par le backoffice et par « Supprimer mon compte ») :
   1. App : afficher l'avertissement Apple si un abonnement App Store est actif (« la facturation continue chez Apple ») avec `showManageSubscriptions`.
   2. API : enregistrer la demande dans le journal d'audit, couper les sessions, mettre en file un job `delete-account`.
   3. Worker : cascade en base, puis préfixes du bucket (ADR-037 §11), puis `DELETE` du client RevenueCat (`404` = déjà fait), puis `bulk_delete` PostHog `{ distinct_ids: [userId], delete_events: true, delete_recordings: true }`. Chaque étape est idempotente et réessayée.
   4. App : `Purchases.logOut()` (quand le SDK sera branché) et `analytics.reset()`, sinon RevenueCat recrée un client anonyme.
6. **PostHog : supprimer après la base**, car un job encore en vol (`activity_processed`…) recréerait la personne avec le même `distinct_id`. Supprimer par `distinct_ids` évite la recherche du `uuid`. Suivre `deletion_status` et noter dans le journal la date de `delete_verified_at`. Il faut une **clé personnelle PostHog** dédiée (scopes `person:read` et `person:write`, hôte `https://eu.posthog.com`), distincte de `POSTHOG_API_KEY`, qui n'est qu'une clé de projet.
7. **Webhooks après suppression** : RevenueCat peut encore envoyer des événements pour l'`app_user_id` d'un compte supprimé (renouvellement Apple, par exemple). `revenuecat_event.user_id` référence `user` : `handleWebhook` doit ignorer, ou enregistrer sans `user_id`, un événement d'utilisateur inconnu au lieu d'échouer en `500`, ce qui provoquerait des réessais.
8. **Délais annoncés à l'athlète** : en base et dans le bucket, la suppression est immédiate. RevenueCat la traite en asynchrone, et PostHog peut prendre jusqu'à environ deux semaines. On peut donc annoncer « supprimé immédiatement, effacement complet chez nos prestataires sous 30 jours », ce que la règle Apple et l'art. 12.3 acceptent. Un e-mail de confirmation est à trancher avec la question « E-mails à l'athlète » de la carte.

---

## Questions ouvertes pour la carte #190

- API RevenueCat v1 ou v2 pour le serveur, et quelle clé met-on dans `REVENUECAT_API_KEY` ?
- Le backoffice propose-t-il des durées prédéfinies (1 mois, 1 an…) ou une date de fin libre ? L'API ne prend plus qu'une date de fin.
- Comment `user_subscription` représente-t-il un Premium promotionnel superposé à un abonnement payant ?
- Suppression immédiate seulement, ou aussi « à la fin de l'abonnement » (option autorisée par Apple) ?
- Un octroi promotionnel crée-t-il le client RevenueCat d'un compte qui n'a jamais ouvert le Paywall ? Et `delete_events` efface-t-il les événements anonymes d'avant `identify` ? Les deux sont à tester en sandbox.
