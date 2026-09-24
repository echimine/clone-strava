# ADR-015 : Analytics et feature flags avec PostHog

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **En lien avec** : [ADR-006](ADR-006-stack-mobile.md), [ADR-007](ADR-007-architecture-mobile.md), [ADR-009](ADR-009-backend-api.md), [ADR-011](ADR-011-backend-worker.md), [ADR-014](ADR-014-revenuecat.md), [ADR-016](ADR-016-experimentation.md)

## Contexte

Il faut comprendre comment l'app est utilisée (activation, rétention, parcours), activer ou désactiver des fonctionnalités à distance, et mener des A/B tests produit (ADR-016). Contraintes :
- données hébergées **dans l'Union européenne** ;
- respect du **RGPD** (consentement, pas de données personnelles inutiles) ;
- pas d'infrastructure lourde à opérer sur le VPS.

## Décision

On utilise **PostHog Cloud EU** pour les analytics produit, les feature flags et les expériences.

### Sources d'événements

| Source | SDK | Événements |
|---|---|---|
| **Mobile** | `posthog-ios` (Swift Package Manager) | Comportement : écrans, actions, onboarding, paywall vu, lecture des flags |
| **Backend** (`api`, `worker`) | `posthog-node` | Événements qui doivent être fiables : `activity_processed`, `activity_failed`, `subscription_started`… (ADR-014) |
| Backoffice | — | Aucun événement (outil interne) |

Le backend est la source des événements « de vérité » : ils ne dépendent pas de l'app (fermée avant l'envoi, hors ligne longtemps).

### Identité

- Avant connexion : identifiant anonyme généré par le SDK.
- Après connexion : `identify(userId)`, **même identifiant** que notre base et RevenueCat. PostHog relie l'historique anonyme au compte.
- À la déconnexion : `reset()`.
- Le backend envoie ses événements avec le même `userId` comme `distinct_id`.

### Données envoyées

- **Aucune donnée personnelle** : pas d'e-mail, de nom, de coordonnées GPS, de tracé, de photo.
- Propriétés utiles et non identifiantes : type de sport, distance arrondie, plateforme, version de l'app, statut premium.
- Enregistrement de sessions (session replay) **désactivé** : les écrans affichent des cartes et des lieux personnels.

### Nommage et catalogue des événements

- Format `objet_action` en snake_case, au passé : `activity_recorded`, `activity_uploaded`, `paywall_viewed`, `onboarding_completed`.
- Catalogue **typé** : côté backend dans `packages/contracts` (nom et propriétés en Zod), côté iOS dans un `enum AnalyticsEvent`. Pas de chaîne libre dans le code.

### Feature flags

- Lus sur le téléphone par le SDK, **mis en cache** : l'app fonctionne hors ligne avec la dernière valeur connue.
- Chaque flag a une **valeur par défaut dans le code** (le comportement actuel), utilisée si PostHog ne répond pas.
- Côté backend : `posthog-node` en **évaluation locale** (définitions des flags téléchargées périodiquement), sans appel réseau par requête.
- Usages : déploiement progressif, coupe-circuit, A/B tests (ADR-016).

### Architecture

- iOS (ADR-007) : protocoles `AnalyticsClient` et `FeatureFlags` dans `Core/`, implémentation PostHog dans l'infrastructure, branchée dans `Di.swift`. Les features n'importent jamais le SDK PostHog. En test : implémentations factices.
- Backend : un module `analytics` dans `packages/core`, utilisé par `api` et `worker`, qui encapsule `posthog-node`.

### Consentement (RGPD)

- Au premier lancement, l'app demande le consentement à la mesure d'audience. **Tant qu'il n'est pas donné, le SDK est en mode refus** (`optOut`) : aucun événement n'est envoyé.
- Le choix est modifiable dans les réglages de l'app.
- Les feature flags fonctionnent sans consentement (pas de suivi) ; seules les mesures d'exposition des expériences dépendent du consentement.
- Pas de suivi entre applications : la demande App Tracking Transparency d'Apple n'est pas nécessaire.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| PostHog auto-hébergé sur le VPS | Très lourd (ClickHouse, Kafka…) pour un petit VPS |
| Firebase Analytics + Remote Config | Données chez Google aux États-Unis, A/B tests moins souples, deux outils |
| Mixpanel / Amplitude | Pas de feature flags intégrés au même niveau, hébergement UE plus limité ou payant |
| Outil de flags séparé (LaunchDarkly, Unleash) | Deux outils à relier ; PostHog réunit analytics, flags et expériences |
| Analytics uniquement depuis le mobile | Événements critiques perdus si l'app est fermée ou hors ligne longtemps |

## Conséquences

### Positives
- Un seul outil pour mesurer, activer à distance et expérimenter.
- Données dans l'UE, sans infrastructure à gérer.
- Événements critiques fiables grâce au backend.
- Identité commune avec RevenueCat : revenus et usage analysables ensemble.

### Négatives / risques
- **Consentement** : une partie des utilisateurs refusera, donc les chiffres sous-estiment l'usage réel.
- **Coût** : palier gratuit généreux, puis facturation au volume d'événements et de requêtes de flags. Vérifier la grille et surveiller les volumes.
- **Dette de flags** : chaque flag doit être supprimé du code une fois inutile (règles dans ADR-016).
- **Catalogue à tenir à jour** des deux côtés (Zod et Swift).

## Références
- PostHog iOS : https://posthog.com/docs/libraries/ios
- PostHog Node : https://posthog.com/docs/libraries/node
- Feature flags : https://posthog.com/docs/feature-flags
- PostHog Cloud EU : https://posthog.com/eu
- [ADR-014 : Abonnements avec RevenueCat](ADR-014-revenuecat.md)
- [ADR-016 : Stratégie d'expérimentation](ADR-016-experimentation.md)
