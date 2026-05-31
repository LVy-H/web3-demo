# ── Stage 1: builder ─────────────────────────────────────────────────────
# Compiles TypeScript + bundles with Vite. VITE_* values are inlined into
# the bundle here — they cannot change after this stage. Override per build
# with `--build-arg VITE_RPC_URL=...` (see docker-compose.yml `build.args`).
FROM node:22-bookworm-slim AS builder
WORKDIR /app

ARG VITE_NETWORK=hardhat
ARG VITE_RPC_URL=http://localhost:8545
ARG VITE_RELAYER_URL=http://localhost:3001
# Opt-in: when "true" AND VITE_NETWORK=hardhat, the bundle includes a wagmi
# `mock` connector pre-loaded with Hardhat account #0 + a "Test Account"
# button in the header. Lets the prod nginx image be usable without MetaMask
# (intended for the loopback-bound docker-compose dev stack). NEVER set this
# to "true" for a build aimed at any real network.
ARG VITE_ENABLE_TEST_ACCOUNT=false
ENV VITE_NETWORK=${VITE_NETWORK} \
    VITE_RPC_URL=${VITE_RPC_URL} \
    VITE_RELAYER_URL=${VITE_RELAYER_URL} \
    VITE_ENABLE_TEST_ACCOUNT=${VITE_ENABLE_TEST_ACCOUNT}

COPY package*.json tsconfig*.json vite.config.ts index.html ./
RUN npm ci
COPY src ./src
COPY public ./public
RUN npm run build

# ── Stage 2: runtime ─────────────────────────────────────────────────────
# nginx-unprivileged runs as uid 101 with no setuid binaries and binds 8080
# by default — no CAP_NET_BIND_SERVICE needed and no root in the container.
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
