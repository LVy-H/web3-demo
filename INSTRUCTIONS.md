# System Usage & Workflow Instructions

Welcome to the ZK Voting and Airdrop system! This document provides a comprehensive guide on how to launch the environment using Docker and the full end-to-end workflow to interact with the system.

## Prerequisites
- **Docker** and **Docker Compose** installed on your system.
- **MetaMask** wallet installed in your browser.

## 1. Starting the Environment

We have containerized the entire local development stack (Hardhat node & React frontend) to ensure a smooth and reproducible startup.

1. **Launch the stack:**
   Open a terminal in the root directory (`web3-demo/`) and run:
   ```bash
   docker compose up --build
   ```
   This command builds the images and starts two services:
   - **`contracts`**: Starts a local Hardhat node on port `8545` and automatically deploys the smart contracts.
   - **`frontend`**: Starts the Vite development server on port `5173`.

2. **Wait for Services to be Ready:**
   Observe the terminal logs. Wait until you see:
   - `contracts` print: "Contracts are fully deployed. Tailing logs..."
   - `frontend` print: "VITE v... ready in ... ms"

3. **Access the Frontend:**
   Open your browser and navigate to [http://localhost:5173](http://localhost:5173).

## 2. Configuring MetaMask

To interact with the smart contracts, you need to connect your MetaMask wallet to the local Hardhat network.

1. Open **MetaMask** and click on the network dropdown at the top left.
2. Select **Add network** -> **Add a network manually**.
3. Fill in the network details:
   - **Network Name**: Hardhat Local
   - **New RPC URL**: `http://127.0.0.1:8545`
   - **Chain ID**: `31337`
   - **Currency Symbol**: `ETH`
4. Click **Save** and switch to this newly added network.

**Funding your Wallet:**
To pay for gas during transactions, you need local test ETH.
1. Open the terminal where `docker compose` is running.
2. Look for the Hardhat node startup logs. It prints a list of 20 accounts and their **Private Keys**.
3. In MetaMask, click on your account icon -> **Import account**.
4. Paste one of the Private Keys provided by Hardhat to import a funded test account.

## 3. Full User Workflow

Here is the step-by-step process of using the ZK Voting and Airdrop systems.

### Phase 1: Registration
1. In the frontend at `http://localhost:5173`, click **Connect MetaMask**.
2. Click **Generate Local Identity**. This creates a Semaphore Zero-Knowledge keypair locally in your browser's `localStorage` to keep you anonymous.
3. Click **Submit Commitment On-chain**. Your MetaMask will prompt you to approve a transaction. This registers your cryptographic identity in the smart contract's voter pool.

### Phase 2: Voting
1. **[Admin Step]** If you deployed the contracts (which the Docker setup does automatically using the first Hardhat account), you have admin rights. Click the **Start Voting** button in the UI to transition the poll.
2. Select either **Candidate A** or **Candidate B**.
3. Click **Generate Proof & Vote**.
   - Your browser will perform complex computations to generate a Zero-Knowledge proof.
   - This proves you are a registered voter *without* revealing your specific identity or Ethereum address.
   - Confirm the transaction in MetaMask.
   - **Note:** The underlying system prevents double voting by tracking a "nullifier hash" tied to your identity. Once used, it blocks any further votes from your identity.

### Phase 3: Lottery & Airdrop Claim
1. **[Admin Step]** Once voting is complete, click **Close & Draw Lottery** to end the poll and allow the prize/airdrop phase to begin.
2. If you are eligible (or won the pseudo-random lottery), a claim section will appear.
3. Enter a **Receiver Address**. Crucially, to maintain privacy, this can be a *completely new, empty Ethereum address* disconnected from the one you used to vote.
4. Click **Verify & Claim Prize**. This generates another ZK proof binding your claim to the chosen payout address and securely sends the prize ETH directly from the contract.

## 4. Stopping the Environment

To shut down the Docker containers and clean up the network, press `Ctrl + C` in the terminal running `docker compose up`, or run:
```bash
docker compose down
```

### Resetting MetaMask (Optional)
Because Hardhat resets its internal state every time you restart the node, MetaMask might get confused by mismatched nonces when the network resets. If transactions fail immediately after a restart:
1. Open MetaMask settings.
2. Go to **Advanced** -> **Clear activity tab data** (or "Reset Account").
