# Ephemeral dev-chain image: Hardhat node + deterministic deploy (+ optional
# demo seed) in one container. Single-stage on purpose: devDependencies
# (hardhat, ts-node) ARE the runtime, so a multi-stage prod-deps split would
# break the entrypoint. No volumes — every start is a fresh chain with the
# same deterministic addresses (hardhat account #0, nonce 0..n).
FROM node:22-bookworm-slim
WORKDIR /app

# curl is used by the entrypoint's RPC readiness probe and the HEALTHCHECK.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY package*.json tsconfig.json hardhat.config.ts ./
RUN npm ci

COPY contracts ./contracts
COPY scripts ./scripts
# Compile at build time: bakes the solc binary + artifacts into the image so
# container startup goes straight to deploy (no compiler download at runtime).
RUN npx hardhat compile
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh \
    && chown -R node:node /app

USER node
EXPOSE 8545

# JSON-RPC readiness: eth_chainId answers as soon as the node is up (deploy
# may still be running — addresses are deterministic, so dependents that only
# need the RPC endpoint can start; the demo seed lands a few seconds later).
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=30 \
  CMD curl -sf -X POST -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
      http://127.0.0.1:8545 > /dev/null || exit 1

ENTRYPOINT ["./docker-entrypoint.sh"]
