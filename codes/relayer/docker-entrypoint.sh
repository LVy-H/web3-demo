#!/bin/bash
set -e

echo "Waiting for Hardhat node to be ready..."
until curl -s --request POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://hardhat:8545 > /dev/null 2>&1; do
  sleep 2
done
echo "Hardhat node is ready!"

echo "Starting relayer service..."
exec npx ts-node src/index.ts
