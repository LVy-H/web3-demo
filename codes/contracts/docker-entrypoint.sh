#!/bin/bash
set -e

echo "Starting hardhat node locally..."
npx hardhat node > hardhat-node.log 2>&1 &
NODE_PID=$!

echo "Waiting for Hardhat node to be ready..."
until curl -s --request POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://127.0.0.1:8545 > /dev/null; do
  sleep 1
done
echo "Hardhat node is running!"

echo ""
echo "====================================================================="
echo "MetaMask Configuration:"
echo "  Network Name:    Hardhat Local"
echo "  RPC URL:         http://127.0.0.1:8545"
echo "  Chain ID:        31337"
echo "  Currency Symbol: ETH"
echo "====================================================================="
echo ""

echo "Deploying contracts..."
npm run deploy:local

echo ""
echo "Contracts deployed. Tailing logs..."
tail -f hardhat-node.log
