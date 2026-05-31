# Single-stage image: Hardhat node + ts-node deploy script live in the same
# container. devDependencies are required at runtime (hardhat, ts-node), so a
# multi-stage prod-deps split would break the entrypoint.
FROM node:22-bookworm-slim
WORKDIR /app

# curl is used by the entrypoint's RPC readiness probe and by the compose
# healthcheck below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY package*.json tsconfig.json hardhat.config.ts ./
RUN npm ci

COPY contracts ./contracts
COPY scripts ./scripts
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh \
    && chown -R node:node /app

USER node
EXPOSE 8545
ENTRYPOINT ["./docker-entrypoint.sh"]
