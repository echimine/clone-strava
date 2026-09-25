# apps/admin — Next.js standalone (ADR-018 §3)
#
# Pattern maison adapté pnpm/Turborepo : turbo prune --docker puis pnpm install --frozen-lockfile
# puis build Turborepo dans le même stage (ne pas copier node_modules entre stages).
# `next.config.ts` a déjà `output: 'standalone'` + `outputFileTracingRoot` (racine du monorepo)
# + `transpilePackages: ['@repo/ui']` (packages/ui reste consommé en source, pas de `pnpm deploy`
# nécessaire ici : Next embarque lui-même un node_modules minimal via file tracing dans
# `.next/standalone`).

# ---- pruner ----
FROM node:24-alpine AS pruner
WORKDIR /app
RUN npm i -g turbo@^2.11.3
COPY . .
RUN turbo prune admin --docker

# ---- builder (install + build fusionnés : ne pas copier node_modules entre stages) ----
FROM node:24-alpine AS builder
WORKDIR /app
RUN npm i -g pnpm@11.25.0
COPY --from=pruner /app/out/json/ .
RUN pnpm install --frozen-lockfile
COPY --from=pruner /app/out/full/ .
# Build-args inlinés dans le bundle navigateur (ADR-018, secrets GitHub) : toute variable
# NEXT_PUBLIC_* utilisée côté client doit être fournie ICI, au build, pas seulement au runtime.
ARG NEXT_PUBLIC_MAPBOX_TOKEN
ENV NEXT_PUBLIC_MAPBOX_TOKEN=${NEXT_PUBLIC_MAPBOX_TOKEN}
RUN pnpm turbo run build --filter=admin

# ---- runner (sortie Next standalone — chemins monorepo) ----
FROM node:24-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
USER node
COPY --chown=node:node --from=builder /app/apps/admin/.next/standalone ./
COPY --chown=node:node --from=builder /app/apps/admin/.next/static ./apps/admin/.next/static
COPY --chown=node:node --from=builder /app/apps/admin/public ./apps/admin/public
EXPOSE 3000
CMD ["node", "apps/admin/server.js"]
