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

echo ""
echo "====================================================================="
echo "MetaMask Local Node Configuration:"
echo "---------------------------------------------------------------------"
echo "Network Name:    Hardhat Local"
echo "New RPC URL:     http://127.0.0.1:8545"
echo "Chain ID:        31337"
echo "Currency Symbol: ETH"
echo ""
echo "Example Account (Account #0):"
grep -m 1 -A 1 "Account #0:" hardhat-node.log || echo "Warning: Could not extract account info from logs"
echo "====================================================================="
echo ""

echo "Deploying system contracts to local node..."
npm run deploy:local

echo ""
echo "====================================================================="
echo "Copying ABIs to frontend..."
npm run copy-abis
echo "====================================================================="
echo ""

echo "Contracts are fully deployed. Tailing logs..."
# Tail the logs in the foreground to keep the docker container running
tail -f hardhat-node.log
