# apps/realtime — NestJS, WebSocket gateway (ADR-018 §3, ADR-010)
# Même pattern que apps/api/Dockerfile (turbo prune + pnpm deploy --prod). Pas de migrations,
# pas de DB directe (Redis pub/sub uniquement). `GET /health` public (ADR-018 §6).

# ---- pruner ----
FROM node:24-alpine AS pruner
WORKDIR /app
RUN npm i -g turbo@^2.11.3
COPY . .
RUN turbo prune realtime --docker

# ---- builder (install + build fusionnés : ne pas copier node_modules entre stages) ----
FROM node:24-alpine AS builder
WORKDIR /app
RUN npm i -g pnpm@11.25.0
COPY --from=pruner /app/out/json/ .
RUN pnpm install --frozen-lockfile
COPY --from=pruner /app/out/full/ .
RUN pnpm turbo run build --filter=realtime
# --legacy : pnpm 10+ refuse par défaut sans inject-workspace-packages=true (cf. apps/api/Dockerfile)
RUN pnpm --filter=realtime deploy --prod --legacy /app/out/realtime

# ---- runner ----
FROM node:24-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
USER node
COPY --chown=node:node --from=builder /app/out/realtime ./
EXPOSE 3001
CMD ["node", "dist/main.js"]
