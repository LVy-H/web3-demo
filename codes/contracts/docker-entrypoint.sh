#!/bin/bash
set -e

echo "Starting hardhat node locally..."
npx hardhat node --hostname 0.0.0.0 > hardhat-node.log 2>&1 &
NODE_PID=$!

echo "Waiting for Hardhat node to be ready..."
# Bounded wait (60 × 1s): fail loudly instead of hanging if the node dies.
for i in $(seq 1 60); do
  if curl -s --max-time 2 --request POST \
       --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
       http://127.0.0.1:8545 > /dev/null 2>&1; then
    echo "Hardhat node is running (attempt ${i})."
    break
  fi
  if ! kill -0 "$NODE_PID" 2>/dev/null; then
    echo "hardhat node exited during startup:" >&2
    cat hardhat-node.log >&2
    exit 1
  fi
  if [ "${i}" -eq 60 ]; then
    echo "hardhat node unreachable after 60s" >&2
    exit 1
  fi
  sleep 1
done

# USE_REAL_VERIFIER=true (env passthrough) deploys the real Groth16
# SemaphoreVerifier instead of the always-true mock — deploy.ts reads it.
echo "Deploying contracts (USE_REAL_VERIFIER=${USE_REAL_VERIFIER:-false})..."
npm run deploy:local

# SEED_DEMO=1 seeds the demo anon-vote poll + demo survey (scripts/demo-poll.ts)
# so a fresh stack has browsable content. Off by default for a blank chain.
if [ "${SEED_DEMO:-0}" = "1" ]; then
  echo "Seeding demo polls (SEED_DEMO=1)..."
  npx hardhat run scripts/demo-poll.ts --network localhost
else
  echo "Skipping demo seed (set SEED_DEMO=1 to seed demo polls)."
fi

echo ""
echo "Chain ready: http://0.0.0.0:8545 (chainId 31337). Tailing node logs..."
exec tail -f hardhat-node.log
