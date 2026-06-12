# ── Stage 1: builder ─────────────────────────────────────────────────────
# Compiles TypeScript → dist/. Carries devDependencies (typescript, @types/*)
# but never ships in the final image.
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY src ./src
RUN npx tsc

# ── Stage 2: runtime ─────────────────────────────────────────────────────
# Slim Alpine runtime with only production deps + compiled dist/ + the
# entrypoint. busybox wget (in the base image) covers the healthcheck and the
# entrypoint's RPC wait — no curl install needed.
# Image digest pinning (FROM ...@sha256:<digest>) is the stronger form; re-pin
# to a digest when a registry-reachable release flow exists.
FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Install runtime-only deps. The `node` user already exists in the base image
# (uid/gid 1000) — we hand the workdir to it before dropping privileges.
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Bring in compiled JS from builder + the entrypoint script.
COPY --from=builder /app/dist ./dist
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh \
    && chown -R node:node /app

USER node
EXPOSE 3001

# /api/relay/info never touches the chain (signer address + registry config
# only) — a cheap liveness + config probe. PORT is env-driven (default 3001),
# so the shell-form expansion follows overrides.
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${PORT:-3001}/api/relay/info" || exit 1

ENTRYPOINT ["./docker-entrypoint.sh"]
