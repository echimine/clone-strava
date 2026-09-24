# ADR-013 : Architecture détaillée du backoffice

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : dossier d'architecture Like-Strava, slide 06 « Architecture backoffice »
- **Détaille** : [ADR-004](ADR-004-backoffice.md)
- **En lien avec** : [ADR-009](ADR-009-backend-api.md), [ADR-012](ADR-012-stack-backoffice.md)

## Contexte

ADR-004 pose le principe : organisation par feature, client HTTP unique, flux Action → Hook → `api.ts` + `apiClient` → API → composant mis à jour. ADR-012 fixe les bibliothèques (TanStack Query, React Hook Form, shadcn dans `packages/ui`, Mapbox GL JS). Il reste à définir l'arborescence complète, le rôle de chaque élément, l'authentification, la communication avec l'API et la gestion des erreurs.

## Décision

### Arborescence

```
apps/admin/src/
├── app/
│   ├── (auth)/login/page.tsx               connexion
│   ├── (admin)/
│   │   ├── layout.tsx                      vérifie la session et le rôle, affiche la navigation
│   │   ├── page.tsx                        tableau de bord
│   │   ├── users/page.tsx
│   │   ├── users/[id]/page.tsx
│   │   ├── activities/page.tsx
│   │   ├── activities/[id]/page.tsx
│   │   └── segments/…
│   └── error.tsx, not-found.tsx
├── features/
│   └── activities/
│       ├── components/                     ActivityTable, ActivityDetail… (composés de @repo/ui)
│       ├── hooks/                          useActivities, useActivity, useDeleteActivity
│       ├── lib/                            utilitaires purs (ex. parseGpx)
│       ├── api.ts                          fonctions typées par endpoint
│       └── query-keys.ts                   clés de cache TanStack Query de la feature
├── components/                             éléments propres à l'app : navigation, en-tête, MapView (Mapbox)
├── lib/
│   ├── apiClient.ts                        client HTTP unique
│   ├── queryClient.ts                      configuration TanStack Query
│   └── auth-client.ts                      client Better Auth
└── proxy.ts                                redirection vers /login sans cookie de session
```

Features prévues pour le MVP (indicatif) : `dashboard`, `users`, `activities`, `segments`, `moderation`.

### Où mettre un composant

| Emplacement | Contenu | Exemple |
|---|---|---|
| `packages/ui` | Composants shadcn et composants génériques, sans métier ni appel API | `Button`, `DataTable`, `ConfirmDialog`, `PageHeader` |
| `apps/admin/src/components` | Éléments propres au backoffice, partagés entre features | Navigation, `MapView` (Mapbox) |
| `features/<feature>/components` | Composants d'une feature | `ActivityTable`, `SegmentEditor` |

### Flux d'une action admin

```
Action administrateur → Hook (TanStack Query) → api.ts → apiClient → API NestJS → invalidation du cache → composant mis à jour
```

| Élément | Rôle | Interdit |
|---|---|---|
| `page.tsx` | Route : mise en page, lecture des paramètres d'URL, assemblage des composants de la feature | Charger des données, appeler l'API |
| Composant de feature | Affiche, déclenche les actions via ses hooks | Appeler `api.ts` ou `apiClient` |
| Hook | `useQuery` pour lire, `useMutation` pour modifier ; invalide les clés concernées après une modification ; affiche un toast de succès ou d'erreur | `fetch` direct |
| `api.ts` | Une fonction typée par endpoint, avec les types de `packages/contracts` | Garder un état |
| `query-keys.ts` | Clés de cache hiérarchiques de la feature (`['activities', 'list', filtres]`, `['activities', id]`) | — |
| `lib/apiClient.ts` | URL de base, cookie de session, JSON, validation des réponses, erreurs normalisées | Connaître le métier |

### Communication avec l'API : même origine via le proxy Next.js

- Le navigateur appelle **`/api/...` sur le domaine du backoffice** ; Next.js relaie ces requêtes vers l'API NestJS (réécritures dans `next.config`).
- Avantages : **pas de CORS**, le **cookie Better Auth** reste sur le domaine du backoffice, l'URL de l'API n'est pas exposée au navigateur.
- Le proxy ne fait que relayer : aucune logique, aucune écriture en base (ADR-004).

### Authentification et autorisation

1. **`proxy.ts`** (le middleware de Next.js) : sans cookie de session, redirection vers `/login`. Simple confort d'interface.
2. **Layout `(admin)`** : récupère l'utilisateur courant par l'API (`GET /v1/me`) ; si la session est invalide → `/login`, si l'utilisateur n'est pas administrateur → page « accès refusé ».
3. **L'API reste la seule garante** : chaque endpoint d'administration vérifie le rôle (ADR-009). Les étapes 1 et 2 n'améliorent que l'expérience.
4. Connexion et déconnexion via le client Better Auth (`lib/auth-client.ts`).

### Erreurs

| Situation | Traitement |
|---|---|
| `401` | Redirection vers `/login` (dans `apiClient`) |
| `403` | Message « accès refusé » |
| `422` / erreur de validation | Erreurs affichées sous les champs du formulaire, à partir des détails renvoyés par l'API (format d'erreur unique, ADR-009) |
| Autre erreur d'une modification | Toast d'erreur (Sonner) |
| Erreur de chargement d'une page | `error.tsx` du segment, avec bouton « réessayer » |

### Tableaux et filtres

- Pagination, tri et filtres **côté serveur** (l'API renvoie une page à la fois).
- L'état des filtres et de la pagination est **dans l'URL** (paramètres de recherche) : une vue filtrée peut être partagée ou rechargée.

### Règles

1. **Aucun accès direct** à PostgreSQL, Redis ou au bucket : aucune dépendance `drizzle-orm`, `pg`, `ioredis` ou SDK S3 dans `apps/admin` (règle ESLint `no-restricted-imports`).
2. **Tout appel réseau passe par `apiClient`.**
3. **Une feature n'importe pas une autre feature** (règle ESLint). Ce qui est partagé remonte dans `src/components`, `src/lib` ou `packages/ui`.
4. **`packages/ui` ne dépend pas de l'app** : pas d'import de `apps/admin`, pas d'appel API.
5. Les types et schémas des échanges viennent **uniquement de `packages/contracts`**.

### Tests

| Cible | Outil |
|---|---|
| Hooks et `api.ts` | Vitest + MSW (API simulée) |
| Composants de feature | Testing Library + MSW |
| Utilitaires (`lib/`) | Vitest |

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Appels directs du navigateur vers l'API (autre domaine) | CORS et configuration des cookies entre domaines à gérer |
| Chargement des données dans les Server Components | Diverge du flux de la slide 06 (hooks) ; TanStack Query gère mieux cache et invalidation pour un outil très interactif |
| Server Actions | Logique côté Next.js au lieu de l'API ; risque de contourner les règles métier |
| Découpage par type de fichier (`components/`, `hooks/` à la racine) | Une feature éclatée dans tout le projet |
| Filtres gardés en mémoire | Perdus au rechargement, vues non partageables |

## Conséquences

### Positives
- Une feature se lit dans un seul dossier ; les routes restent minces.
- Pas de CORS ni de cookie entre domaines grâce au proxy.
- Autorisation centralisée dans l'API.
- Données cohérentes après chaque action grâce aux clés de cache par feature.

### Négatives / risques
- **Proxy Next.js** : un saut réseau de plus entre le navigateur et l'API (négligeable pour un outil interne) ; en-têtes (IP, identifiant de corrélation) à transmettre correctement.
- **Chargement côté client** : premier affichage avec état de chargement.
- **Règles ESLint** à mettre en place dès le départ pour que les interdits soient vérifiés automatiquement.

## Références
- Dossier d'architecture Like-Strava, slide 06
- [ADR-004 : Stack et architecture du backoffice](ADR-004-backoffice.md)
- [ADR-009 : Backend · app api](ADR-009-backend-api.md)
- [ADR-012 : Stack détaillée du backoffice](ADR-012-stack-backoffice.md)
- TanStack Query, clés de cache : https://tanstack.com/query/latest/docs/framework/react/guides/query-keys
