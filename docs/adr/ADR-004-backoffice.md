# ADR-004 : Stack et architecture du backoffice

- **Statut** : accepted
- **Date** : 2026-09-24
- **Décideurs** : echimine
- **Source** : dossier d'architecture Like-Strava, slides 05 « Stack · backoffice » et 06 « Architecture backoffice »
- **Dépend de** : [ADR-001](ADR-001-architecture-globale.md), [ADR-003](ADR-003-backend.md)

## Contexte

La plateforme a besoin d'une application web d'administration, réservée à l'équipe : gestion des utilisateurs, modération des contenus, gestion des segments, suivi de la plateforme. La priorité est la productivité de développement et des écrans de gestion standards (tableaux, formulaires, filtres, dialogues).

## Décision

### Stack

| Brique | Choix | Rôle |
|---|---|---|
| Framework | **Next.js** (App Router) | Application web |
| Langage | **TypeScript** | Code typé |
| Styles | **Tailwind CSS** | Styles utilitaires |
| Composants | **shadcn/ui** | Composants d'administration, copiés dans le code et modifiables |

### Principes

1. **Le backoffice est un client de l'API**, comme le mobile (ADR-001). Il ne contacte **jamais directement PostgreSQL**, ni Redis.
2. **Rôle administrateur vérifié par l'API** sur chaque endpoint d'administration (Better Auth, ADR-003). La protection des pages côté Next.js améliore l'expérience mais ne constitue pas la sécurité.
3. **Pas de temps réel** : le backoffice n'est relié qu'à l'API (ADR-001).

### Architecture : organisation par feature

```
src/
├── app/admin/<feature>/page.tsx      route : mise en page et assemblage
├── features/<feature>/
│   ├── components/                   UI de la feature (shadcn/ui)
│   ├── hooks/                        le « controller » : état, chargement, actions
│   ├── lib/                          utilitaires propres à la feature (ex. parseGpx)
│   └── api.ts                        appels API typés de la feature
└── lib/apiClient.ts                  client HTTP unique vers l'API
```

Flux d'une action admin :

```
Action administrateur → Hook (controller) → api.ts + apiClient → API NestJS → Composant mis à jour
```

- Tout appel réseau passe par `lib/apiClient.ts` (URL de base, session, erreurs normalisées).
- Une feature n'importe pas une autre feature.
- Les DTO sont typés à partir de `packages/contracts` (ADR-005).

Le détail (chargement des données, cache, gestion des erreurs) sera précisé dans un ADR dédié.

## Alternatives envisagées

| Option | Pourquoi écartée |
|---|---|
| Admin généré (AdminJS, React Admin) | Branché sur la base ou sur des conventions d'API imposées, contourne les règles métier |
| Outil low-code (Retool, Appsmith) | Dépendance SaaS, coût par utilisateur, accès aux données hors de notre code |
| Server Actions avec accès direct à la base | Contourne l'API et ses règles (contredit ADR-001) |
| MUI / Ant Design | Thème lourd à personnaliser, dépendance forte |

## Conséquences

### Positives
- Règles métier et d'accès centralisées dans l'API : l'admin ne peut rien faire que l'API n'autorise pas.
- Même langage que le backend, contrats Zod partagés.
- Même logique de découpage par feature que le mobile et le backend.

### Négatives / risques
- **Endpoints d'administration à développer** dans l'API pour chaque besoin.
- **Sécurité** : journaliser les actions d'administration (qui, quoi, quand), prévoir à terme une double authentification.
- **Exposition** : `noindex`, et restriction réseau possible (sous-domaine dédié, liste d'IP).
- **CORS et cookies** : évités grâce au proxy Next.js vers l'API (ADR-013).

## Références
- Dossier d'architecture Like-Strava, slides 05 et 06
- [ADR-001 : Architecture globale](ADR-001-architecture-globale.md)
- [ADR-003 : Backend](ADR-003-backend.md)
- Next.js : https://nextjs.org/docs
- shadcn/ui : https://ui.shadcn.com
