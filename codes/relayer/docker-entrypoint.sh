#!/bin/sh
set -e

# Belt-and-suspenders next to compose's `depends_on: service_healthy`: wait for
# the chain RPC named by RPC_URL (the same env config.ts reads) so a bare
# `docker run` also comes up cleanly. Bounded: 60 × 1s, then fail loudly rather
# than hanging forever (unbounded waits hide real misconfigurations like wrong
# service hostnames or compose network issues).
RPC="${RPC_URL:-http://chain:8545}"
echo "Waiting for chain RPC at ${RPC}..."
i=1
while [ "$i" -le 60 ]; do
  if wget -q -O /dev/null --header 'Content-Type: application/json' \
       --post-data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
       "$RPC" 2>/dev/null; then
    echo "Chain RPC is ready (attempt ${i})."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "chain RPC unreachable after 60s: ${RPC}" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

echo "Starting relayer service..."
exec node dist/index.js
