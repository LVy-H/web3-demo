# ── Stage 1: builder ─────────────────────────────────────────────────────
# Compiles TypeScript → dist/. Carries devDependencies (typescript, @types/*)
# but never ships in the final image.
FROM node:22-bookworm-slim AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY src ./src
RUN npx tsc

# ── Stage 2: runtime ─────────────────────────────────────────────────────
# Slim image with only production deps + compiled dist/ + entrypoint.
# Image digest pinning (FROM ...@sha256:<digest>) is the stronger form
# but requires registry access; the manifest lookup was unreachable from
# the build host at patch time. Re-pin to a digest once reachable.
FROM node:22-bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Install runtime-only deps. `node` user already exists in the base image
# (uid/gid 1000) - we hand the workdir to it before dropping privileges.
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Bring in compiled JS from builder + the entrypoint script.
COPY --from=builder /app/dist ./dist
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh \
    && chown -R node:node /app

USER node
EXPOSE 3001
ENTRYPOINT ["./docker-entrypoint.sh"]
