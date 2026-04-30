# Contracts — ZK Voting Hub

Hardhat project containing the modular ZK voting smart contracts.

## Stack

| Library | Version | Purpose |
|---------|---------|---------|
| Hardhat | 2.28 | Development framework |
| Solidity | 0.8.34 | Smart contract language |
| @semaphore-protocol/contracts | 4 | ZK group + proof verification |
| @openzeppelin/contracts | 5 | EIP-1167 minimal proxy (Clones) |
| Chai + ethers.js | — | Testing |

## Commands

```bash
npm install          # Install dependencies
npm test             # Run all tests
npm run compile      # Compile contracts
npm run node         # Start local Hardhat node at http://127.0.0.1:8545
npm run deploy:local # Deploy to the running local node
npm run copy-abis    # Copy compiled ABIs to frontend/ and relayer/
```

## Contracts

### `PollRegistry.sol`

EIP-1167 minimal proxy factory. Creates poll instances by cloning registered module implementations.

| Function | Access | Description |
|----------|--------|-------------|
| `registerModule(type, impl)` | Owner | Register a module implementation address |
| `createPoll(type, title, desc, initData)` | Public | Clone a module and initialize it |
| `getAllPolls()` | View | List all created polls |
| `getPollCount()` | View | Total number of polls |

### `ZkAnonVoting.sol` (Module M1)

Anonymous voting using Semaphore ZK proofs. Voters receive invite tokens off-chain, load them in the browser to derive a Semaphore identity, and vote without revealing their wallet address.

| Function | Access | Description |
|----------|--------|-------------|
| `initialize(semaphore, owner, options)` | Once | Initialize clone (replaces constructor) |
| `registerVoter(commitment)` | Owner | Register a single voter identity |
| `registerVoters(commitments[])` | Owner | Batch register voter identities |
| `addOption(label)` | Owner | Add a voting option (Registration only) |
| `startVoting()` | Owner | Transition to Voting phase |
| `castVote(vote, proof)` | Public | Submit anonymous vote with ZK proof |
| `endVoting()` | Owner | Close the poll |
| `getState()` | View | Current phase (0=Registration, 1=Voting, 2=Ended) |
| `getResults()` | View | Vote counts per option |

### `ZkBlindVoting.sol` (Module M2)

Commit-reveal blind voting. Voters register by wallet address, commit a hash of their vote, then reveal after voting ends.

| Function | Access | Description |
|----------|--------|-------------|
| `initialize(owner, options, revealDuration)` | Once | Initialize clone |
| `register()` | Public | Register wallet as voter |
| `commitVote(hash)` | Registered | Submit vote commitment |
| `revealVote(optionIndex, salt)` | Committed | Reveal vote during reveal window |
| `startVoting()` | Owner | Start voting phase |
| `endVoting()` | Owner | End voting, open reveal window |
| `finalizeResults()` | Owner | Lock results after reveal window |

### `ZkAirdrop.sol`

Semaphore-gated anonymous ETH airdrop. Members prove group membership to claim funds without revealing identity.

### `MockSemaphoreVerifier.sol`

Test-only verifier that always returns `true`. Never deploy to a live network.

## Deployment Addresses (fresh Hardhat node)

| Contract | Address |
|----------|---------|
| PoseidonT3 | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| MockSemaphoreVerifier | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| Semaphore | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |
| PollRegistry | `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9` |
| ZkAnonVoting (impl) | `0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9` |
| ZkBlindVoting (impl) | `0x0165878A594ca255338adfa4d48449f69242Eb8F` |
| ZkAirdrop | `0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6` |

## Tests

Tests use `MockSemaphoreVerifier` — runs entirely offline, no SNARK downloads.

```bash
npm test
```

Test suites: `PollRegistry.test.ts`, `ZkAnonVoting.test.ts`, `ZkBlindVoting.test.ts`
