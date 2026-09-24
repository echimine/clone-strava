# ADR-016 : Stratégie d'expérimentation (A/B tests)

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Dépend de** : [ADR-014](ADR-014-revenuecat.md) (RevenueCat), [ADR-015](ADR-015-posthog.md) (PostHog)

## Contexte

On veut vérifier par la mesure si un changement est meilleur que l'existant : un prix, un paywall, mais aussi un écran d'onboarding, la place d'un bouton, le contenu d'un résumé d'activité. Deux outils savent faire des A/B tests : **RevenueCat Experiments** et **PostHog Experiments**. Sans règles, on risque de tester la même chose dans les deux outils, de fausser les résultats ou d'accumuler des flags morts dans le code.

## Décision

### Qui teste quoi

| Ce qu'on teste | Outil | Mesuré par |
|---|---|---|
| **Monétisation** : prix, durée, essai gratuit, offre recommandée, variante de paywall | **RevenueCat Experiments** (un offering par groupe, variantes d'affichage via les métadonnées, ADR-014) | Conversion, revenu, rétention des abonnés |
| **Produit** : onboarding, écrans, parcours, textes, fonctionnalités | **PostHog Experiments** (flag à plusieurs variantes, ADR-015) | Événements PostHog (activation, rétention, usage) |

**Règle** : tout ce qui touche au paywall et aux prix passe **uniquement** par RevenueCat. PostHog ne pilote jamais le paywall, pour éviter que deux expériences se superposent sur le même écran.

### Cycle de vie d'une expérience

1. **Hypothèse écrite** : « Si on montre la carte dans le résumé d'activité, plus d'utilisateurs enregistreront une deuxième activité dans la semaine. »
2. **Indicateur principal** unique (ex. `second_activity_recorded` sous 7 jours) et **indicateurs de garde** qui ne doivent pas se dégrader (ex. taux de crash, désinstallations, conversion premium).
3. **Taille d'échantillon et durée** calculées avant le lancement (calculateur de l'outil). Durée minimale d'une semaine complète, pour couvrir les habitudes de la semaine et du week-end.
4. **Lancement** : répartition aléatoire, le plus souvent 50/50.
5. **Pas d'arrêt anticipé** parce qu'un résultat « a l'air bon » : on attend la taille d'échantillon prévue. Seule exception : un indicateur de garde qui se dégrade nettement.
6. **Décision** : on garde la variante gagnante, ou le contrôle si l'écart n'est pas significatif.
7. **Nettoyage** : le flag et la variante perdante sont **supprimés du code dans les deux semaines** qui suivent la décision.

### Nommage des flags PostHog

| Préfixe | Usage | Exemple |
|---|---|---|
| `exp-` | Expérience A/B, durée limitée | `exp-onboarding-3-ecrans` |
| `ff-` | Déploiement progressif d'une fonctionnalité | `ff-segments-live` |
| `kill-` | Coupe-circuit permanent | `kill-upload-arriere-plan` |

### Règles dans le code

- La variante est lue dans le **store ou le service** via le protocole `FeatureFlags` (ADR-015), jamais directement dans la vue.
- **Valeur par défaut = contrôle** : si le flag n'est pas disponible, l'utilisateur voit le comportement actuel.
- Le flag est lu **au moment où l'utilisateur voit l'élément testé** : c'est ce qui enregistre son exposition. Le lire trop tôt compterait des utilisateurs qui n'ont jamais vu la variante.
- Une expérience qui modifie aussi un comportement serveur lit le flag **côté backend** avec le même `userId`, pour que l'app et l'API voient la même variante.
- Pas plus de quelques expériences simultanées, et **jamais deux expériences sur le même écran**.

### Volume d'utilisateurs

Un A/B test ne donne un résultat fiable qu'avec assez d'utilisateurs. Tant que le nombre d'utilisateurs est faible :
- on privilégie les **déploiements progressifs** (`ff-`) et l'observation des indicateurs ;
- on ne lance une expérience que si la taille d'échantillon calculée est atteignable dans un délai raisonnable (quelques semaines).

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Tout tester dans PostHog, y compris les prix | PostHog ne connaît pas les revenus réels des abonnements aussi bien que RevenueCat, et ne pilote pas les offres de l'App Store |
| Tout tester dans RevenueCat | RevenueCat ne teste que les offerings et le paywall |
| Pas de règles communes | Expériences superposées, résultats faussés, flags oubliés dans le code |

## Conséquences

### Positives
- Chaque type de test a un outil clair, sans chevauchement.
- Décisions fondées sur des résultats significatifs plutôt que sur l'intuition.
- Code propre : les flags ont une durée de vie limitée et un nommage explicite.

### Négatives / risques
- **Discipline** : hypothèse, taille d'échantillon et nettoyage demandent de la rigueur à chaque test.
- **Peu d'utilisateurs au début** : la plupart des tests seront peu concluants ; il faudra l'accepter.
- **Consentement** (ADR-015) : les utilisateurs qui refusent la mesure ne comptent pas dans les résultats PostHog.

## Références
- PostHog Experiments : https://posthog.com/docs/experiments
- RevenueCat Experiments : https://www.revenuecat.com/docs/tools/experiments-v1
- [ADR-014 : Abonnements avec RevenueCat](ADR-014-revenuecat.md)
- [ADR-015 : Analytics et feature flags avec PostHog](ADR-015-posthog.md)
