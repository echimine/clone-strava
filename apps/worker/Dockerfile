# apps/worker — NestJS application context, SANS serveur HTTP (ADR-018 §3, ADR-011)
# Même pattern que apps/api/Dockerfile (turbo prune + pnpm deploy --prod). Healthcheck =
# fichier heartbeat /tmp/worker-alive rafraîchi toutes les 15s (ADR-018 §6), voir compose
# (healthcheck défini côté docker-compose.yml, pas de HEALTHCHECK Dockerfile ici).

# ---- pruner ----
FROM node:24-alpine AS pruner
WORKDIR /app
RUN npm i -g turbo@^2.11.3
COPY . .
RUN turbo prune worker --docker

# ---- builder (install + build fusionnés : ne pas copier node_modules entre stages) ----
FROM node:24-alpine AS builder
WORKDIR /app
RUN npm i -g pnpm@11.25.0
COPY --from=pruner /app/out/json/ .
RUN pnpm install --frozen-lockfile
COPY --from=pruner /app/out/full/ .
RUN pnpm turbo run build --filter=worker
RUN pnpm --filter=worker deploy --prod /app/out/worker

# ---- runner ----
FROM node:24-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
USER node
COPY --chown=node:node --from=builder /app/out/worker ./
CMD ["node", "dist/main.js"]
