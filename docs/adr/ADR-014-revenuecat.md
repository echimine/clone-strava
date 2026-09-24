# ADR-014 : Abonnements avec RevenueCat

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **En lien avec** : [ADR-006](ADR-006-stack-mobile.md), [ADR-007](ADR-007-architecture-mobile.md), [ADR-009](ADR-009-backend-api.md), [ADR-011](ADR-011-backend-worker.md), [ADR-015](ADR-015-posthog.md), [ADR-016](ADR-016-experimentation.md)

## Contexte

L'app propose un **abonnement premium** (fonctionnalités avancées, à définir), vendu par achat intégré sur iOS. Il faut :
- vendre et renouveler les abonnements via l'App Store (StoreKit) ;
- savoir, **dans l'app et dans l'API**, si un utilisateur est premium ;
- afficher un **paywall au design propre à l'app** ;
- pouvoir **tester des prix, des durées d'essai et des variantes de paywall** sans publier de nouvelle version.

Gérer StoreKit directement impose de valider les reçus, suivre les renouvellements, remboursements et périodes de grâce, et calculer les revenus soi-même.

## Décision

On utilise **RevenueCat** pour les achats intégrés, avec un **paywall SwiftUI maison**.

### Côté iOS

| Sujet | Choix |
|---|---|
| SDK | **`purchases-ios`** (RevenueCat) via Swift Package Manager ; pas de `RevenueCatUI` |
| Paywall | **Écran SwiftUI maison**, alimenté par l'**offering courant** de RevenueCat (produits, prix localisés, essai) |
| Droits | Un **entitlement** `premium` ; l'app lit `CustomerInfo` pour afficher ou masquer les fonctionnalités |
| Identité | `Purchases.logIn(userId)` après la connexion (même identifiant que notre base et PostHog), `logOut()` à la déconnexion |
| Obligations App Store | Bouton « Restaurer mes achats », liens vers les conditions et la politique de confidentialité, gestion de l'abonnement via les réglages iOS |

**Paywall piloté à distance malgré le code maison :**
- Les **prix, durées et essais** viennent des offerings : les changer ne demande pas de nouvelle version.
- Les **métadonnées d'offering** (JSON configurable dans RevenueCat) pilotent les variantes d'affichage codées dans l'app : titre, argument mis en avant, offre recommandée, variante de mise en page (`"layout": "A"` ou `"B"`).
- Une variante de paywall qui n'existe pas encore dans le code demande une nouvelle version.

**Architecture (ADR-007)** : le paywall est une feature `Features/Paywall`. Le SDK RevenueCat reste dans `Infrastructure/`, derrière un protocole du domaine (`SubscriptionService` : offres, achat, restauration, statut). Les autres features ne connaissent que ce protocole.

### Côté backend

L'app ne fait pas foi pour l'API : l'API doit savoir elle-même si un utilisateur est premium.

1. RevenueCat envoie un **webhook** à l'API : `POST /v1/webhooks/revenuecat`, authentifié par un en-tête secret configuré dans RevenueCat.
2. L'API vérifie le secret, enregistre l'événement (dédupliqué par son identifiant) et **met un job en file** (`sync-subscription`), puis répond `200` immédiatement.
3. Le worker récupère l'**état complet de l'abonné via l'API REST de RevenueCat** (plutôt que de se fier à l'ordre des webhooks) et met à jour le statut premium de l'utilisateur en base.
4. Le worker envoie aussi l'événement à PostHog (`subscription_started`, `subscription_renewed`, `subscription_cancelled`…) pour relier revenus et usage (ADR-015).
5. Les endpoints réservés au premium vérifient ce statut en base.

La table qui stocke le statut d'abonnement n'existe pas dans le modèle de la slide 09 : elle sera ajoutée dans l'ADR sur le modèle de données.

### A/B tests de monétisation

Les tests de **prix, durées, essais et variantes de paywall** passent par **RevenueCat Experiments** : chaque groupe reçoit un offering différent, et RevenueCat mesure conversion, revenu et rétention. Règles communes dans ADR-016.

### Prérequis

- **Compte Apple Developer payant** et accord « Paid Apps » signé dans App Store Connect : **obligatoire**, y compris pour tester en sandbox. **Bloquant tant que la question du compte n'est pas réglée.**
- Produits d'abonnement créés dans App Store Connect, clé d'API In-App Purchase et notifications serveur App Store configurées vers RevenueCat.
- Fichier de configuration StoreKit dans Xcode pour tester localement sans App Store Connect au début du développement.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| StoreKit 2 seul, sans RevenueCat | Validation, renouvellements, remboursements, webhooks et statistiques de revenu à développer soi-même ; pas d'A/B test de prix |
| RevenueCat Paywalls (`RevenueCatUI`) | Moins de liberté de design ; les métadonnées d'offering donnent déjà une partie du pilotage à distance |
| Adapty, Qonversion, Superwall | Fonctionnellement proches ; RevenueCat est le plus répandu et le mieux documenté |
| Statut premium lu uniquement dans l'app | L'API ne peut pas protéger les fonctionnalités premium côté serveur |
| Traitement du webhook directement dans l'API (sans worker) | Appel à RevenueCat pendant la réponse au webhook ; en cas de panne, dépendance au nombre limité de renvois de RevenueCat |
| Appliquer le contenu du webhook sans relire l'état complet | Webhooks possiblement en désordre, en double ou perdus : risque de statut faux |
| Endpoint `POST /v1/subscriptions/sync` appelé par l'app après un achat | Réduirait le délai avant que l'API voie le premium, mais le webhook suffit pour le MVP ; ajout possible plus tard si le délai gêne |

## Conséquences

### Positives
- Achats, renouvellements et remboursements gérés sans code serveur spécifique à Apple.
- Prix et offres modifiables et testables sans nouvelle version.
- Paywall au design de l'app.
- Statut premium connu de l'API, donc des fonctionnalités premium protégées côté serveur.

### Négatives / risques
- **Compte Apple Developer requis** avant toute implémentation réelle.
- **Coût** : RevenueCat est gratuit jusqu'à un certain revenu mensuel suivi, puis prélève un pourcentage. Vérifier la grille tarifaire en vigueur.
- **Dépendance** à un service tiers pour l'état des abonnements (l'App Store reste la vraie source).
- **Paywall maison** : chaque nouvelle variante de mise en page demande une version de l'app.
- **Délai accepté** : entre l'achat et la réception du webhook (généralement quelques secondes), l'API peut ne pas encore voir l'utilisateur comme premium. L'app se fie à `CustomerInfo` pour l'affichage immédiat. On attend le webhook, sans synchronisation déclenchée par l'app.

## Références
- RevenueCat iOS : https://www.revenuecat.com/docs/getting-started/installation/ios
- Offerings et métadonnées : https://www.revenuecat.com/docs/tools/offering-metadata
- Webhooks : https://www.revenuecat.com/docs/integrations/webhooks
- Experiments : https://www.revenuecat.com/docs/tools/experiments-v1
- [ADR-015 : Analytics et feature flags avec PostHog](ADR-015-posthog.md)
- [ADR-016 : Stratégie d'expérimentation](ADR-016-experimentation.md)
