#!/bin/bash
set -e

echo "Waiting for Hardhat node to be ready..."
# Bounded wait: up to 60 attempts × 1s = 60s. After that, fail loudly
# rather than hanging forever (unbounded waits hide real misconfigurations
# like wrong service hostnames or compose network issues).
for i in $(seq 1 60); do
  if curl -s --max-time 2 --request POST \
       --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
       http://contracts:8545 > /dev/null 2>&1; then
    echo "Hardhat node is ready (attempt ${i})."
    break
  fi
  if [ "${i}" -eq 60 ]; then
    echo "hardhat unreachable after 60s" >&2
    exit 1
  fi
  sleep 1
done

echo "Starting relayer service..."
exec node dist/index.js
