# ADR-012 : Stack détaillée du backoffice

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Détaille** : [ADR-004](ADR-004-backoffice.md) (stack et architecture du backoffice)
- **En lien avec** : [ADR-005](ADR-005-monorepo.md), [ADR-009](ADR-009-backend-api.md), [ADR-013](ADR-013-architecture-backoffice.md)

## Contexte

ADR-004 a fixé les grandes briques du backoffice (Next.js, TypeScript, Tailwind CSS, shadcn/ui) et son principe : un client de l'API, sans accès à la base ni temps réel. Il reste à choisir les bibliothèques pour les données, les formulaires, les tableaux, l'authentification, la carte, et la façon de gérer les composants shadcn dans le monorepo.

Le backoffice est un **outil interne**, en **français uniquement**.

## Décision

| Besoin | Choix |
|---|---|
| Framework | **Next.js** (App Router), React 19, TypeScript |
| Styles | **Tailwind CSS v4** (configuration dans le CSS, variables de thème partagées) |
| Composants | **shadcn/ui**, installés **via le serveur MCP shadcn** dans **`packages/ui`** |
| Icônes | **lucide-react** (bibliothèque par défaut de shadcn) |
| Données serveur | **TanStack Query v5** : cache, chargement, invalidation après modification, retries |
| Formulaires | **React Hook Form** + résolveur **Zod**, avec les schémas de `packages/contracts` |
| Tableaux | **TanStack Table**, selon le modèle « data table » de shadcn |
| Authentification | Client **Better Auth** (`better-auth/react`), session par cookie |
| Carte | **Mapbox GL JS** (`mapbox-gl`) |
| Graphiques | Composants **Chart** de shadcn (basés sur Recharts) |
| Notifications à l'écran | **Sonner** (composant `sonner` de shadcn) |
| Dates | **date-fns** avec la locale `fr` |
| Langue | **Français uniquement**, textes écrits directement dans le code, pas de bibliothèque d'i18n |
| Tests | **Vitest** + **Testing Library**, **MSW** pour simuler l'API |

### shadcn/ui : composants dans `packages/ui`, ajoutés via le MCP

- Les composants shadcn vivent dans **`packages/ui`**, partagé dans le monorepo (ADR-005). `apps/admin` les importe depuis `@repo/ui`.
- Le projet utilise le **mode monorepo de shadcn** : un `components.json` dans `packages/ui` (cible des composants) et un dans `apps/admin`, avec les alias vers `@repo/ui/components`, `@repo/ui/lib` et `@repo/ui/hooks`.
- **Tout ajout de composant passe par le serveur MCP shadcn** (recherche, consultation, puis installation dans `packages/ui`), configuré dans `.mcp.json` du dépôt. On n'écrit pas à la main un composant qui existe dans le registre shadcn.
- Les styles globaux et les variables de thème (`globals.css`) sont dans `packages/ui` et importés par l'app.
- Les composants de `packages/ui` restent **génériques** : aucun appel à l'API, aucune connaissance métier (ADR-013).
- Les fichiers actuels de `packages/ui` (`button.tsx`, `card.tsx`, `code.tsx` du template create-turbo) seront remplacés par les composants shadcn.

### Carte : Mapbox GL JS

- Même fournisseur que le mobile (ADR-002) : **mêmes styles Mapbox Studio**, rendu cohérent entre l'app et le backoffice.
- Usages : afficher le tracé d'une activité signalée, **valider et corriger les segments**.
- Composant **client uniquement** (chargement dynamique sans rendu serveur), propre à `apps/admin` : `mapbox-gl` n'entre pas dans `packages/ui`.
- Jeton Mapbox public dédié au backoffice, **restreint aux URLs du backoffice**.

## Alternatives envisagées

| Sujet | Alternative | Pourquoi écartée |
|---|---|---|
| Composants | Composants shadcn copiés dans chaque app | Duplication dès qu'une deuxième app web existera ; `packages/ui` est déjà prévu (ADR-005) |
| Composants | Ajout manuel (copier-coller depuis le site) | Le MCP garantit la bonne version, les bonnes dépendances et le bon emplacement |
| Données serveur | `useEffect` + `fetch` à la main | Cache, invalidation, retries et états de chargement à réécrire dans chaque hook |
| Données serveur | SWR | Moins complet pour les mutations et l'invalidation |
| Formulaires | Formik / formulaires non contrôlés à la main | React Hook Form est le standard de shadcn et s'intègre à Zod |
| Carte | MapLibre GL JS | Styles et tuiles à fournir soi-même ; Mapbox garde la cohérence avec le mobile |
| Carte | Leaflet | Pas de rendu vectoriel ni de styles Mapbox |
| Langue | next-intl dès le départ | Inutile pour un outil interne en français ; ajout possible plus tard |

## Conséquences

### Positives
- Un seul endroit pour les composants et le thème, réutilisable par une future app web.
- Formulaires validés côté client avec les **mêmes schémas Zod** que l'API.
- Données toujours à jour après une action (invalidation TanStack Query), sans code répétitif.
- Carte identique à celle du mobile.

### Négatives / risques
- **Mode monorepo de shadcn** : alias et `components.json` à configurer correctement dans les deux projets, sinon le MCP installe au mauvais endroit.
- **Composants copiés** : les mises à jour de shadcn ne sont pas automatiques ; on les réinstalle via le MCP si besoin.
- **Coût Mapbox** : le backoffice consomme aussi des chargements de carte (faible pour un usage interne).
- **Pas d'i18n** : si le backoffice doit un jour être traduit, il faudra extraire les textes.

## Références
- [ADR-004 : Stack et architecture du backoffice](ADR-004-backoffice.md)
- [ADR-013 : Architecture détaillée du backoffice](ADR-013-architecture-backoffice.md)
- shadcn/ui monorepo : https://ui.shadcn.com/docs/monorepo
- shadcn/ui MCP : https://ui.shadcn.com/docs/mcp
- TanStack Query : https://tanstack.com/query
- React Hook Form : https://react-hook-form.com
- Mapbox GL JS : https://docs.mapbox.com/mapbox-gl-js/
