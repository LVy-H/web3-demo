#!/bin/bash
set -e

# Start hardhat node in the background and redirect output
echo "Starting hardhat node locally..."
npx hardhat node > hardhat-node.log 2>&1 &
NODE_PID=$!

echo "Waiting for Hardhat node to be ready..."
# Poll the JSON-RPC interface until it responds successfully
until curl -s --request POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://127.0.0.1:8545 > /dev/null; do
  sleep 1
done
echo "Hardhat node is successfully running!"

echo "Deploying system contracts to local node..."
npm run deploy:local

echo "Contracts are fully deployed. Tailing logs..."
# Tail the logs in the foreground to keep the docker container running
tail -f hardhat-node.log
