# apps/api — NestJS (ADR-018 §3-4)
#
# Pattern maison (skill deploy-vps), adapté pnpm/Turborepo :
#   pruner  -> turbo prune --docker : ne garde que l'app + ses packages internes + un lockfile élagué
#   builder -> pnpm install --frozen-lockfile puis build Turborepo, dans le MEME stage
#              (ne pas copier node_modules entre stages : perdrait les node_modules par workspace),
#              puis `pnpm deploy --prod` produit un node_modules autonome, sans devDependencies
#   runner  -> node:24-alpine, user non-root `node`, ne copie que la sortie de `pnpm deploy`
#
# Migrations : PAS d'entrypoint dédié ici. `apps/api/src/main.ts` appelle déjà
# `runMigrations(config.DATABASE_URL)` (packages/db, drizzle) avant NestFactory.create
# (ADR-018 §4). Il faut donc que `packages/db/drizzle/` (SQL) soit présent au runtime :
# `pnpm deploy --prod` embarque les `files` du package (`dist` + `drizzle`, cf. package.json).

# ---- pruner ----
FROM node:24-alpine AS pruner
WORKDIR /app
RUN npm i -g turbo@^2.11.3
COPY . .
RUN turbo prune api --docker

# ---- builder (install + build fusionnés : ne pas copier node_modules entre stages) ----
FROM node:24-alpine AS builder
WORKDIR /app
RUN npm i -g pnpm@11.25.0
# Manifests élagués d'abord (cache Docker sur l'install)
COPY --from=pruner /app/out/json/ .
RUN pnpm install --frozen-lockfile
# Sources complètes élaguées (app + packages internes uniquement)
COPY --from=pruner /app/out/full/ .
RUN pnpm turbo run build --filter=api
# Sortie autonome (prod only) dans /app/out/api, sans devDependencies
RUN pnpm --filter=api deploy --prod /app/out/api

# ---- runner ----
# `init: true` côté docker-compose (tini) gère le forwarding de signaux : pas besoin
# d'un init process supplémentaire dans l'image.
FROM node:24-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
USER node
COPY --chown=node:node --from=builder /app/out/api ./
EXPOSE 3001
CMD ["node", "dist/main.js"]
