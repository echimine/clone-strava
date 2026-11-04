# Recherche : règles App Store sur le contenu généré par les utilisateurs et la suppression de compte

- **Ticket** : [#192 Règles App Store : contenu généré par les utilisateurs et suppression de compte](https://github.com/echimine/clone-strava/issues/192) (carte wayfinder [#190](https://github.com/echimine/clone-strava/issues/190) « Backoffice Nervo »)
- **Date** : 2026-11-04
- **Question** : qu'exigent les App Store Review Guidelines pour Nervo sur (1) le contenu généré par les utilisateurs (guideline 1.2 : filtrer, signaler, bloquer, délai de réponse, conditions d'utilisation, contact publié ; le blocage entre athlètes est-il exigé ?) et (2) la suppression de compte (guideline 5.1.1(v) : bouton dans l'app, étapes de confirmation, suppression immédiate ou différée, abonnement actif, Sign in with Apple, anonymisation ou effacement) ?
- **Contexte Nervo** : Activités publiques ou réservées aux abonnés, commentaires, kudos, Médias (photos, vidéos), profils avec bio et Avatar, Follows. Connexion par Google ou Sign-in code par e-mail, pas de Sign in with Apple pour l'instant (ADR-022). Premium via RevenueCat (ADR-014). Prévu : bouton « Signaler » (commentaire, Activité, athlète), file de modération dans le backoffice, bouton « Supprimer mon compte ».
- **Sources** : [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (page « Last Updated: October 16, 2026 ») ; page App Review [5.1.1(v) - Offering account deletion in your app](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion) (l'ancienne URL `developer.apple.com/support/offering-account-deletion-in-your-app/` y redirige, page non datée) ; Human Interface Guidelines [Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts) ; StoreKit [`showManageSubscriptions(in:)`](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(in:)) ; [TN3194 : Handling account deletions and revoking tokens for Sign in with Apple](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple) (publié le 2025-10-03) ; App Store Connect [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/) ; documentation RevenueCat ([API v1 Customers](https://www.revenuecat.com/docs/api-v1/customers), [Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile)). Tout lu le **2026-11-04**. Les citations sont verbatim, en anglais.
- **Source secondaire, signalée comme telle** : le texte type d'un rejet 1.2 recopié par un développeur sur les [Apple Developer Forums (thread 807358, novembre 2025)](https://developer.apple.com/forums/thread/807358). Ce n'est pas un texte publié par Apple ; c'est pourtant la seule trace du délai de 24 h et du blocage « par les utilisateurs ».
- **Non vérifié** : aucune soumission réelle. Ce qui suit est la lecture des textes, pas un retour d'App Review sur Nervo.

Conventions : **Fait** = ce que dit une source, avec son lien. **Recommandation** = mon avis pour Nervo, à trancher dans la carte.

---

## TL;DR

1. **Nervo est une app à contenu généré** au sens de 1.2 (Activités, commentaires, Médias, bio, Avatar). Elle doit offrir **les quatre moyens** listés : filtrer le contenu répréhensible avant publication, le signaler avec une réponse rapide, bloquer les utilisateurs abusifs, publier un contact.
2. **Le blocage entre athlètes est, en pratique, exigé.** Le texte de 1.2 dit seulement *« The ability to block abusive users from the service »*, ce qui pourrait se lire comme un bannissement par nous. Mais le message de rejet type d'App Review demande *« A mechanism for users to block abusive users »*, donc un bouton « Bloquer » côté athlète. Il faut les deux : blocage par l'athlète et bannissement depuis le backoffice.
3. **Délai de réponse** : la guideline dit *« timely responses »* sans chiffre. Le message de rejet type dit **24 h** : retirer le contenu et *« ejecting the user »*. Il exige aussi des **conditions d'utilisation acceptées** qui affichent une tolérance zéro (EULA). Ces deux points ne figurent pas dans le texte public des guidelines.
4. **Suppression de compte** : elle doit pouvoir **démarrer dans l'app**, être facile à trouver (réglages du compte) et supprimer **le compte et toutes ses données, y compris le contenu partagé** (photos, vidéos, posts). Une simple désactivation ne suffit pas. Pas de passage obligé par un e-mail, un chat ou le support.
5. **Confirmation** : demander une confirmation et une **ré-authentification par code envoyé à l'e-mail du compte** est explicitement admis. Notre Sign-in code convient. Un parcours *« unnecessarily difficult »* est rejeté.
6. **Délai** : une suppression non immédiate est admise si elle prend *« a reasonable amount of time »*. Il faut dire combien de temps elle prendra et **confirmer quand c'est fait**. Une suppression **programmée plus tard** (par exemple à la fin de l'abonnement) est admise **seulement si une option de suppression immédiate existe aussi**.
7. **Abonnement actif** : prévenir que la facturation **continue via Apple** et demander de résilier avant de continuer, avec `showManageSubscriptions` / `manageSubscriptionsSheet` ou le lien `https://apps.apple.com/account/subscriptions/`. Ni nous ni RevenueCat ne pouvons résilier un abonnement Apple. Supprimer le client RevenueCat ne touche pas à l'abonnement.
8. **Sign in with Apple** (pour plus tard) : révoquer les jetons via `/auth/revoke` à la suppression et traiter la notification `consent-revoked` (TN3194).
9. **Hors question mais à savoir** : avec un fil d'Activités, des kudos et des commentaires, Nervo coche probablement la capacité « Social Media » du questionnaire d'âge, ce qui donne **13+**. La guideline 4.8 (Google impose une alternative comme Apple) est déjà traitée dans ADR-022.

---

## 1. Contenu généré par les utilisateurs (guideline 1.2)

### Faits

Texte de la guideline ([App Store Review Guidelines, 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)) :

> Apps that enable users to create, generate, upload, share, or otherwise contribute content present particular challenges, including intellectual property infringement, nonconsensual intimate imagery, and anonymous bullying. This includes social media, user-generated content platforms, and AI content creation apps. To prevent abuse, such apps must include:
>
> - A method for filtering objectionable material from being posted to the app
> - A mechanism to report offensive content and timely responses to concerns
> - The ability to block abusive users from the service
> - Published contact information so users can easily reach you

Suite du même article :

> It is your responsibility to remove content that violates this guideline, your terms of service, or your community standards. Developers who fail to implement appropriate safeguards or fail to remediate identified violations after notice may be considered in violation of the Developer Code of Conduct. If we find such content, we will ask you to remove it, and provide a plan to improve your compliance with this guideline. Based on your response, your app may be removed from the App Store until you can demonstrate improvements that bring your app into compliance. Egregious or repeated behavior is grounds for immediate removal of your app from the App Store, and from the Apple Developer Program.

> Apps with user-generated content or services that end up being used primarily for pornographic content, Chatroulette-style experiences, random or anonymous chat, objectification of real people (such as "hot-or-not" voting), making physical threats, or bullying do not belong on the App Store and may be removed without notice.

- **1.2.1 Creator Content** (âge vérifié ou déclaré pour le contenu au-delà de la classification) vise les apps de « creators » qui monétisent des expériences. **Pas le cas de Nervo.**
- La même liste de quatre moyens réapparaît en **4.7.1** (mini-apps, chatbots, plug-ins) : *« include a method for filtering objectionable material, a mechanism to report content and timely responses to concerns, and the ability to block abusive users »*. Apple la considère donc comme un socle standard.
- **Aucun délai chiffré** dans les guidelines : seulement *« timely responses to concerns »*.
- **Aucune mention d'EULA ou de conditions d'utilisation** dans 1.2. Les guidelines parlent de *« your terms of service, or your community standards »* comme base de retrait.
- **Contact publié** : 1.2 exige *« Published contact information so users can easily reach you »*. Indépendamment, 5.1.1(i) impose un lien vers la politique de confidentialité *« within the app in an easily accessible manner »*, qui doit *« Explain its data retention/deletion policies and describe how a user can revoke consent and/or request deletion of the user's data »*.

### Ce que dit le message de rejet type (source secondaire)

Un développeur recopie sur les forums Apple ([thread 807358](https://developer.apple.com/forums/thread/807358), novembre 2025) les « Next Steps » d'un rejet 1.2 :

> To resolve this issue, please revise your app to implement the following precautions:
>
> - Require that users agree to terms (EULA) and these terms must make it clear that there is no tolerance for objectionable content or abusive users
> - A method for filtering objectionable content
> - A mechanism for users to flag objectionable content
> - A mechanism for users to block abusive users
> - The developer must act on objectionable content reports within 24 hours by removing the content and ejecting the user who provided the offending content

Lors d'un second rejet, le même développeur cite aussi : *« A mechanism for users to immediately remove posts from the feed »*. D'autres fils du forum titrés « Guideline 1.2 - Safety - User Generated Content » existent (par exemple [688227](https://developer.apple.com/forums/thread/688227)), mais seul le fil 807358 a été lu en entier. Le seul message d'App Review dans le fil 807358 renvoie vers App Store Connect, sans rien préciser.

Lecture : **ce que les relecteurs vérifient est plus strict que le texte public**. En particulier :

| Point | Texte public (1.2) | Message de rejet type |
|---|---|---|
| Blocage | *« block abusive users from the service »* (ambigu : nous, ou l'utilisateur ?) | *« A mechanism for **users** to block abusive users »* : côté utilisateur |
| Délai | *« timely »* | **24 h**, retrait du contenu **et** exclusion de l'auteur |
| Conditions d'utilisation | absentes | **EULA acceptée**, tolérance zéro explicite |
| Effet du blocage | non précisé | *« immediately remove posts from the feed »* |

« Ejecting the user » n'est pas défini (suspension du compte ou interdiction de publier ?). Aucune réponse officielle trouvée.

### Ce qui déclenche typiquement un rejet 1.2

D'après le texte type ci-dessus : un des cinq points absent ou introuvable par le relecteur. En pratique, le relecteur doit **pouvoir tester** signalement et blocage avec le compte de démo exigé par 2.1(a) (*« include demo account info (and turn on your back-end service!) if your app includes a login »*). Les notes de review sont l'endroit où décrire le filtre, la modération et l'engagement de 24 h.

### Recommandations

- **Bloquer un athlète** dans l'app, depuis son profil et depuis le menu d'un commentaire. Effet immédiat pour celui qui bloque : ses Activités, commentaires et Médias disparaissent du fil et des listes, les Follows dans les deux sens sont supprimés, il ne peut plus suivre, commenter ni donner de kudos. Une liste « Athlètes bloqués » dans les réglages permet de débloquer.
- **Signaler** un commentaire, une Activité (donc ses Médias) ou un athlète (bio, Avatar, nom). Le contenu signalé est **masqué tout de suite pour celui qui signale**, ce qui répond à « immediately remove posts from the feed ».
- **File de modération dans le backoffice** avec un objectif de **traitement en moins de 24 h** : retirer le contenu, **suspendre ou bannir** l'auteur (le « ejecting »). Les rôles et le délai sont à tracer dans la carte #190.
- **Filtre avant publication** : liste de mots interdits sur les textes (commentaires, titre et description d'Activité, bio, nom). Rien n'exige explicitement une détection automatique d'images ; le signalement plus la modération couvrent les Médias. À reconsidérer si la volumétrie grandit.
- **Conditions d'utilisation acceptées** à l'inscription (Onboarding), avec une clause de tolérance zéro pour le contenu répréhensible et les utilisateurs abusifs, plus un lien permanent dans les réglages.
- **Contact publié** : adresse de support visible dans l'app (réglages > aide) et URL de support dans App Store Connect.

---

## 2. Suppression de compte (guideline 5.1.1(v))

### Faits : la règle

Texte de la guideline ([5.1.1(v) Account Sign-In](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)) :

> If your app supports account creation, you must also offer account deletion within the app.

Page App Review ([5.1.1(v) - Offering account deletion in your app](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)) :

> Apps submitted to the App Store that support account creation must also let people initiate deletion of their account within the app.
>
> Deleting an account removes the account from the developer's records, along with any data associated with the account that the developer isn't legally required to maintain.

Les quatre consignes (même page, « Account deletion guidance ») :

> - Make the account deletion option easy to find in your app. Typically, it's included in the app's account settings.
> - Offer to delete the entire account record, along with associated personal data. You may include additional options, but only offering to temporarily deactivate or disable an account is insufficient.
> - If people need to visit a website to finish deleting their account, include a link directly to the page on your website where they can complete the process. […]
> - Keep people informed. If the deletion request will take additional time to complete, let them know. If your app supports in-app purchases, help people understand how billing and cancellations will be handled. If you're legally required to retain some user information, let people know what information will and won't be retained.

Les obligations s'appliquent **à tout le monde**, pas seulement aux régions RGPD ou CCPA (FAQ : *« Everyone should be able to delete their accounts, regardless of where they're located. »*). TN3194 date l'obligation : *« as of June 30, 2022 »*.

### Faits : étapes de confirmation et support

FAQ de la page App Review :

> **Can I direct people to a customer service flow to complete account deletion?** It depends. Apps in highly regulated industries, as described in App Review Guideline 5.1.1(ix), may use additional customer service flows […]. Apps not operating in highly regulated industries should not require people to make a phone call, send an email, use a chat support flow, or go through other support flows.

> **Can I require reauthentication or add confirmation steps […]?** Yes. It's appropriate to confirm the user genuinely intends to delete their account. You may add steps to verify the identity of the person making the request, and to confirm that they want to delete the account, such as by entering a code from an email or phone number already associated with the account. However, apps that make it unnecessarily difficult for someone to delete their account will not pass review.

Apple ne donne **pas de nombre maximal d'étapes**. Le critère est « unnecessarily difficult ». La HIG ajoute ([Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)) : *« Make the link easy to discover — for example, don't bury it in your Privacy Policy or Terms of Service pages. »* et *« Provide a consistent account-deletion experience whether people perform it within your app or game or on the website. »*

Nervo (sport, réseau social) n'entre pas dans les « highly regulated fields » de 5.1.1(ix) (*« banking and financial services, healthcare, gambling, legal cannabis use, air travel and crypto exchanges »*).

### Faits : immédiate ou différée

FAQ de la page App Review :

> **I manually delete accounts and this takes time. Does account deletion need to be immediate and automatic?** No. If your process for account deletion is manual or otherwise takes a reasonable amount of time to complete, this is acceptable. Inform the person how long it will take to delete the account and provide a confirmation when the deletion is complete. Ensure the time it takes to delete accounts complies with local laws where your app is available.

HIG ([Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)) :

> Consider letting people schedule account deletion to occur in the future. People can appreciate the opportunity to use their remaining services or wait until their subscription auto-renews before deleting their account. If you offer a way to schedule account deletion, offer an option for immediate deletion as well.

> Tell people when account deletion will complete, and notify them when it's finished.

Apple **ne parle pas explicitement** d'un « délai de grâce » pendant lequel la personne peut annuler sa demande en se reconnectant. Les textes admettent (a) un traitement qui prend un temps raisonnable, annoncé puis confirmé, et (b) une suppression programmée **à condition qu'une option immédiate existe**. Ils refusent une désactivation seule.

### Faits : abonnement actif

FAQ de la page App Review :

> **How do I handle people with auto-renewable subscriptions?** If a person has an auto-renewable subscription, notify them that billing will continue through Apple and ask them to cancel their subscription before continuing. If you use App Store Server Notifications for auto-renewable subscriptions, you can verify the status of the person's subscription in real time, or use the Subscription Status API to identify subscription status.
>
> Use showManageSubscriptions in iOS 15 and iPadOS 15, or later, or provide this link to let people manage their subscriptions: https://apps.apple.com/account/subscriptions/. […]
>
> You can also use beginRefundRequest in iOS 15 and iPadOS 15, or later, or provide this Apple Support link to let customers submit refund requests: https://support.apple.com/118223.
>
> Additionally, you can offer to schedule account deletion for a later date, aligned with the subscription's expiration, as long as there's also an option to delete the account immediately.

HIG ([Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)) : à expliquer à la personne,

> - Billing for an auto-renewable subscription continues through Apple until people cancel the subscription, regardless of whether they delete their account.
> - After they delete their account, people need to cancel their subscription or request a refund.

et : *« Even if people didn't use your app to purchase the subscription, you still need to support account deletion. »*

StoreKit ([`showManageSubscriptions(in:)`](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(in:))) : iOS 15.0+, *« Presents the App Store sheet for managing subscriptions »*. La feuille propose *« the options to view, upgrade, downgrade, or cancel their subscription »*. En SwiftUI : *« call the `manageSubscriptionsSheet(isPresented:)` view modifier »*.

RevenueCat :

- *« Permanently deletes a customer. Deletion is queued asynchronously. »* et *« After a `200`, treat a `404` as confirmation that the customer no longer exists. »* ([API v1 Customers](https://www.revenuecat.com/docs/api-v1/customers), `DELETE /subscribers/{app_user_id}`).
- *« Deleting customers through the RevenueCat dashboard or API clears out all of their data »*, ce qui couvre une demande d'effacement RGPD. Supprimer le client **ne résilie pas** l'abonnement : *« It's not possible for you to cancel a customer's Apple subscription »* ([Customer Profile](https://www.revenuecat.com/docs/dashboard-and-metrics/customer-profile)).

### Faits : ce qui compte comme « suppression »

FAQ de la page App Review :

> **Does the content provided by a person need to be deleted in apps that display and share user-generated content?** Yes. People expect that all data associated with their account will be deleted when the account is deleted. This includes user-generated content that's shared with others, such as photos, videos, text posts, and reviews. If local laws or regulations require you to maintain some data, let people know.

Donc : **effacement**, pas une anonymisation du contenu partagé. Apple ne parle pas explicitement de l'anonymisation. La règle vise *« any data associated with the account »* ; une donnée réellement détachée du compte (statistique agrégée) n'est plus « associée », mais c'est une interprétation, pas un texte.

### Faits : Sign in with Apple (pour mémoire)

- Page App Review : *« Apps that support Sign in with Apple should use the Sign in with Apple REST API to revoke user tokens. Use server-to-server notification endpoints to process changes for Sign in with Apple accounts. »*
- HIG : *« If people used Sign in with Apple to create an account within your app, you revoke the associated tokens when they delete their account. »*
- [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple) : l'endpoint `/auth/revoke` *« is the only way to programmatically invalidate user tokens »* et demande un refresh token ou un access token valide. Il faut donc **stocker le refresh token** à la connexion (valider le code via `/auth/token`). Sans jeton, il faut quand même supprimer les données et inviter la personne à révoquer l'accès à la main. Côté app, observer `credentialRevokedNotification` ; côté serveur, traiter l'événement `consent-revoked` en supprimant les données (y compris le jeton) et en revenant à un état déconnecté. Sans révocation, à la reconnexion Apple ne redemande ni nom ni e-mail.
- 5.1.1(v) ajoute, pour les réseaux sociaux : *« The app must also include a mechanism to revoke social network credentials and disable data access between the app and social network from within the app. »* Google n'est pas un réseau social au sens de cet exemple (*« Facebook, WeChat, Weibo, X »*). Supprimer le compte efface de toute façon les jetons Google stockés par Better Auth.

### Recommandations

- **Emplacement** : Réglages > Compte > « Supprimer mon compte », visible sans fouiller. Pas seulement dans la politique de confidentialité.
- **Parcours** : un écran qui explique ce qui sera supprimé (Activités, Médias, commentaires, kudos, Follows, profil) et ce qui est conservé pour obligation légale s'il y en a ; puis une ré-authentification par **Sign-in code** envoyé à l'e-mail du compte ; puis la confirmation. Deux étapes, c'est défendable ; pas de questionnaire obligatoire de « pourquoi partez-vous ».
- **Délai** : si on veut un délai de grâce (par exemple 30 jours pendant lesquels la reconnexion annule la demande), le compte doit **disparaître tout de suite pour les autres** (contenu masqué, profil invisible), le délai doit être **annoncé** et un **e-mail de confirmation** envoyé à la fin. Proposer aussi « Supprimer immédiatement » pour coller à la HIG. Le plus simple à défendre en review : suppression immédiate (effacement en tâche de fond par le worker, en quelques minutes ou heures) plus e-mail de confirmation.
- **Abonnement actif** : si RevenueCat indique un Premium actif, afficher avant la confirmation : « Ton abonnement continue d'être facturé par Apple tant que tu ne l'as pas résilié », avec un bouton qui ouvre `manageSubscriptionsSheet`. Ne pas bloquer la suppression si la personne ne résilie pas. On peut offrir en option « Supprimer à la fin de l'abonnement » à côté de « Supprimer maintenant ». Côté serveur : `DELETE` du client RevenueCat et déconnexion du SDK (`logOut`) pour éviter qu'il ne soit recréé.
- **Effacement** : supprimer les commentaires et kudos de la personne sur les Activités des autres, pas les remplacer par « Utilisateur supprimé ». Supprimer les fichiers Médias et Avatar dans le stockage objet. Supprimer la personne dans PostHog. Les signalements la concernant peuvent garder une trace minimale si une obligation légale le justifie, à dire dans la politique de confidentialité.
- **Politique de confidentialité** (5.1.1(i)) : décrire la durée de conservation et comment demander la suppression.
- **Compte de démo** : le relecteur peut supprimer le compte de démo pendant le test. Prévoir de le recréer, ou le signaler dans les notes de review.

---

## 3. Hors question, mais utile pour la soumission

- **Classification d'âge** ([Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)) : « User-Generated Content » reste en **4+**, mais « Social Media » (*« Redistribution, amplification, or interaction with user-generated content through a social feed or similar discovery method that visibly spreads content to many users. May include: feeds that allow users to engage with and amplify user-generated content through features such as views, likes, comments, and shares. »*) place l'app en **13+**. Le fil, les kudos et les commentaires de Nervo correspondent probablement à cette définition. Le questionnaire est à remplir honnêtement (2.3.6).
- **Connexion** ([4.8](https://developer.apple.com/app-store/review/guidelines/#login-services)) : une app qui utilise Google Sign-In doit offrir *« as an equivalent option another login service »* qui limite la collecte au nom et à l'e-mail, permet de **garder son e-mail privé** et ne trace pas pour la publicité. Le Sign-in code par e-mail ne permet pas de cacher son e-mail, donc ne suffit probablement pas. ADR-022 l'a déjà noté : pas de soumission avant Sign in with Apple.
- **RGPD** (hors Apple, à faire valider) : Apple renvoie aux lois locales pour le délai. Le RGPD (art. 12(3)) prévoit une réponse à une demande d'effacement dans un délai d'un mois.
