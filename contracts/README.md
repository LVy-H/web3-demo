# Contracts — ZK Ballot & Lottery

Hardhat project for the ZK Ballot & Lottery PoC smart contracts.

## Stack

| Library | Version | Purpose |
|---------|---------|---------|
| Hardhat | 2.28 | Development framework |
| Solidity | 0.8.34 | Smart contract language |
| @semaphore-protocol/contracts | 4 | ZK group + proof verification |
| @semaphore-protocol/identity | 4 | Off-chain keypair generation |
| @semaphore-protocol/group | 4 | Off-chain Merkle tree |
| Chai + ethers.js | — | Testing |

## Commands

```bash
npm install          # Install dependencies
npm test             # Run all tests
npm run compile      # Compile contracts
npm run node         # Start local Hardhat node at http://127.0.0.1:8545
npm run deploy:local # Deploy to the running local node
```

## Contracts

### `ZkVotingLottery.sol`

The main PoC contract. Orchestrates three phases:

1. **Registration** – voters register their Semaphore identity commitment.
2. **Voting** – voters submit an anonymous ZK proof to cast a vote.
3. **Ended** – a pseudo-random winner is drawn; winner claims the prize with another ZK proof.

**Key functions:**

| Function | Access | Description |
|----------|--------|-------------|
| `registerVoter(uint256 commitment)` | Public | Register a Semaphore identity (Phase 1 only) |
| `startVoting()` | Owner | Advance from Registration → Voting |
| `castVote(uint256 vote, SemaphoreProof proof)` | Public | Submit a ZK-verified anonymous vote |
| `endVotingAndDrawLottery()` | Owner | End voting, draw lottery winner |
| `claimPrize(address receiver, SemaphoreProof proof)` | Public | Winner claims prize to a fresh address |
| `voteCounts(uint256 candidate)` | View | Vote tally for candidate 1 or 2 |
| `winningNullifier()` | View | Nullifier of the lottery winner |
| `prizeClaimed()` | View | Whether the prize has been claimed |

### `MockSemaphoreVerifier.sol`

A test-only ZK verifier that always returns `true`.

> **Never deploy this to a live network.** It is only used in Hardhat tests so that SNARK artifacts do not need to be downloaded.

## Deployment Addresses (fresh Hardhat node)

These addresses are deterministic on a fresh Hardhat node (deployer `0xf39Fd6…`, nonce starts at 0):

| Contract | Address |
|----------|---------|
| PoseidonT3 | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| SemaphoreVerifier | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| Semaphore | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |
| **ZkVotingLottery** | **`0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9`** |

## Tests

Tests use `MockSemaphoreVerifier` so they run **entirely offline** — no SNARK circuit downloads required.

```
ZkVotingLottery
  ✔ Should allow voters to register in the registration phase
  ✔ Should reject registration during voting phase
  ✔ Should reject double voting via nullifier reuse
  ✔ Should execute a full ZK voting, lottery, and prize-claim flow
```

## Security Notes (PoC limitations)

- **Lottery randomness** — uses `keccak256(block.timestamp, block.prevrandao, blockhash)`. This is manipulable by block proposers. Replace with Chainlink VRF for production.
- **Group state** — the frontend mirrors the on-chain group locally. In production, derive it from `VoterRegistered` event history.
- **No prize funds** — the `receive()` function accepts ETH but no ETH is sent in the deploy script. Send ETH to the contract before running the lottery for a real prize.
