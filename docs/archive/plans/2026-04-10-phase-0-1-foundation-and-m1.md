# Anonymous Web3 System: Phase 0-1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the codebase into a modular architecture with a shared `IZkPoll` interface and `PollRegistry` factory, then refactor the existing ZkVoting PoC (M1) to fit this architecture with hardened tests and improved UX.

**Architecture:** Modular contracts behind a shared interface (`IZkPoll`). A `PollRegistry` factory deploys poll instances as EIP-1167 minimal proxies. The existing `ZkVoting.sol` is refactored to implement `IZkPoll` and initialize via `initialize()` instead of a constructor. The frontend is refactored to read polls from the Registry and interact via the shared interface.

**Tech Stack:** Solidity ^0.8.20, Hardhat, Semaphore v4, React 19, Vite, Wagmi v3, TypeScript strict mode, Playwright E2E.

---

## File Structure

### New Files to Create

```
codes/contracts/contracts/
├── interfaces/
│   └── IZkPoll.sol              -- Shared interface for all voting modules
├── PollRegistry.sol             -- Factory + registry, deploys minimal proxies
├── ZkAnonVoting.sol             -- Refactored M1 (replaces ZkVoting.sol)
└── (ZkVoting.sol)               -- Deleted after migration

codes/contracts/test/
├── IZkPoll.test.ts              -- Interface compliance tests
├── PollRegistry.test.ts         -- Registry factory tests
└── ZkAnonVoting.test.ts         -- Refactored M1 tests (replaces ZkVotingTokenFlow.ts)

codes/frontend/src/
├── abi/
│   ├── IZkPoll.json             -- Shared ABI
│   ├── PollRegistry.json        -- Registry ABI
│   └── ZkAnonVoting.json        -- M1 ABI
├── hooks/
│   ├── useRegistry.ts           -- Hook for PollRegistry reads/writes
│   └── usePoll.ts               -- Hook for IZkPoll interactions
├── pages/
│   ├── Home.tsx                 -- Refactored to use Registry hook
│   └── Poll.tsx                 -- Refactored to use IZkPoll hook
└── config.ts                    -- Updated with Registry address

codes/contracts/scripts/
└── deploy.ts                    -- Updated for new architecture

docs/
├── framework/
│   ├── privacy-dimensions.md
│   └── module-comparison.md
└── architecture/
    ├── system-overview.md
    └── module-m1-anon-voting.md
```

### Files to Modify
- `codes/contracts/hardhat.config.ts` -- No changes needed (solidity 0.8.34 compatible)
- `codes/frontend/src/App.tsx` -- Minor: update imports
- `codes/frontend/src/config.ts` -- Add REGISTRY_ADDRESS
- `codes/frontend/src/main.tsx` -- No changes needed
- `codes/docker-compose.yml` -- Already updated

### Files to Delete (after migration)
- `codes/contracts/contracts/ZkVoting.sol` -- Replaced by ZkAnonVoting.sol
- `codes/contracts/contracts/ZkVotingFactory.sol` -- Replaced by PollRegistry.sol
- `codes/contracts/test/ZkVotingTokenFlow.ts` -- Replaced by new test files
- `codes/frontend/src/ZkVoting.json` -- Replaced by abi/
- `codes/frontend/src/ZkVotingFactory.json` -- Replaced by abi/
- `codes/frontend/src/ZkVotingLottery.json` -- Unused legacy file

---

## Phase 0: Foundation

### Task 1: Write Framework Documentation

**Files:**
- Create: `docs/framework/privacy-dimensions.md`
- Create: `docs/framework/module-comparison.md`

- [ ] **Step 1: Write the Privacy Dimensions Framework doc**

```markdown
# Privacy Dimensions Framework

## Overview

This system models privacy as **3 independent axes** rather than a linear tier system.
Each voting module selects a position on each axis. No position is inherently "better" --
they solve different problems with different trade-offs.

## Axes

### 1. Identity: Who voted?

| Position | Description | Example |
|----------|-------------|---------|
| `anonymous` | ZK proof of membership. No address link. Observer cannot determine which group member voted. | Semaphore nullifier-based voting |
| `pseudonymous` | Wallet address visible on-chain, but real-world identity unknown. | Standard DAO voting (Snapshot) |
| `identified` | Address visible and tied to a known identity (e.g., via SBT or KYC). | Corporate governance with identity verification |

### 2. Content: What did they vote?

| Position | Description | Example |
|----------|-------------|---------|
| `public-realtime` | Individual votes visible as they are cast. Anyone can see who voted for what. | Snapshot governance |
| `public-aggregate` | Running tally visible, but individual votes cannot be traced to voters. | Module M1 (ZK anonymous + live tally) |
| `sealed` | All votes hidden until a reveal trigger (time or threshold). | Commit-reveal elections |
| `forever-blind` | Individual votes never revealed. Only aggregate result exists. | FHE-based tallying |

### 3. Temporality: When is information revealed?

| Position | Description | Example |
|----------|-------------|---------|
| `immediate` | Information available as soon as the action occurs. | Live tally updates |
| `threshold` | Revealed when N votes or N% participation reached. | "Results after 50 votes" |
| `time-locked` | Revealed after a deadline. | "Results on Friday at 5pm" |
| `never` | Information is permanently sealed. | Forever-blind vote content |

## Impossible Combinations

Some axis positions conflict:

1. **Anonymous identity + public-realtime content in small groups**: If 5 voters exist and 4 voted "Yes," the 5th is deanonymized by elimination.
2. **Sealed content + immediate temporality**: Contradictory by definition.
3. **Anonymous identity + direct participation proof**: The receipt itself must be a ZK proof ("I'm in the voter set"), not a direct identity claim. This is possible but requires careful construction.

## Module Mapping

| Module | Identity | Content | Temporality |
|--------|----------|---------|-------------|
| M1: Anonymous Token Voting | anonymous | public-aggregate | immediate |
| M2a: Blind Voting (live tally) | identified | public-aggregate | immediate |
| M2b: Blind Voting (sealed) | identified | sealed | threshold / time-locked |
| M3: Participation Receipt | (cross-cutting feature) | -- | on-demand |
```

- [ ] **Step 2: Write the Module Comparison doc**

```markdown
# Voting Module Comparison

## Which module should I use?

### "I want voters to be completely anonymous"
Use **M1: Anonymous Token Voting**.
- Nobody (not even the admin) can link a vote to a person.
- Voters prove membership via ZK proof.
- Live tally visible, but individual votes untraceable.
- Trade-off: Requires invite token distribution. Cannot track who participated (by design).

### "I need to know who voted but not what they voted"
Use **M2a: Blind Voting (Live Tally)** or **M2b: Blind Voting (Sealed)**.
- Voter addresses recorded on-chain. Admin can see participation.
- Vote content is encrypted or committed -- individual choices hidden.
- M2a shows running aggregate tally. M2b hides everything until reveal trigger.
- Trade-off: Voters are not anonymous. Their participation is public.

### "I want results hidden until enough people vote"
Use **M2b: Blind Voting (Sealed)** with a threshold trigger.
- No results visible during voting phase.
- Results revealed only after N votes received or deadline passes.
- Prevents bandwagon effects and strategic voting.
- Trade-off: Voters must return to reveal (commit-reveal). Non-revealers lose their vote.

### "I need proof that someone voted"
Add **M3: Participation Receipt** to any module.
- For M1: ZK proof of participation (anonymous receipt).
- For M2: Signed attestation + on-chain event verification.
- Off-chain receipt format: JSON file the voter can share.
- Verifiable by anyone via the contract's `verifyParticipation()` method.

## Feature Matrix

| Feature | M1 (Anon) | M2a (Blind Live) | M2b (Blind Sealed) |
|---------|-----------|-------------------|---------------------|
| Voter anonymity | Yes | No | No |
| Vote content hidden | Yes (aggregate only) | Yes (aggregate only) | Yes (until reveal) |
| Live tally | Yes | Yes | No |
| Participation tracking | No | Yes | Yes |
| Participation receipt | ZK proof | Signed attestation | Signed attestation |
| Sybil resistance | Token-gated | Address-gated | Address-gated |
| Crypto primitives | Semaphore ZK | ElGamal / simplified | Commit-reveal |
```

- [ ] **Step 3: Commit framework docs**

```bash
git add docs/framework/privacy-dimensions.md docs/framework/module-comparison.md
git commit -m "docs: add privacy dimensions framework and module comparison guide"
```

---

### Task 2: Define IZkPoll Interface

**Files:**
- Create: `codes/contracts/contracts/interfaces/IZkPoll.sol`

- [ ] **Step 1: Write the IZkPoll interface**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IZkPoll - Shared interface for all voting modules
/// @notice Every voting module implements this interface. The PollRegistry and
///         frontend code against IZkPoll without knowing the underlying module.
interface IZkPoll {
    /// @notice Poll lifecycle states shared across all modules.
    enum PollState {
        Registration,
        Voting,
        Ended
    }

    /// @notice Emitted when the poll transitions to a new state.
    event StateChanged(PollState newState);

    /// @notice Returns the current lifecycle state of the poll.
    function getState() external view returns (PollState);

    /// @notice Returns the vote tally per option.
    /// @dev Array index corresponds to option index. Values may be 0 if the
    ///      module hides results until reveal (sealed mode returns empty until revealed).
    function getResults() external view returns (uint256[] memory);

    /// @notice Returns the list of poll option labels.
    function getOptions() external view returns (string[] memory);

    /// @notice Returns the total number of registered participants.
    function getParticipantCount() external view returns (uint256);

    /// @notice Returns the poll owner / creator address.
    function owner() external view returns (address);

    /// @notice Verifies that a given nullifier hash was used in this poll.
    /// @param nullifierHash The nullifier to check.
    /// @return True if the nullifier was consumed (i.e., someone with that
    ///         nullifier participated).
    function verifyParticipation(uint256 nullifierHash) external view returns (bool);
}
```

- [ ] **Step 2: Compile to verify syntax**

Run: `cd codes/contracts && npx hardhat compile`
Expected: Compilation successful (interface only, no implementation yet)

- [ ] **Step 3: Commit**

```bash
git add codes/contracts/contracts/interfaces/IZkPoll.sol
git commit -m "feat: add IZkPoll shared interface for all voting modules"
```

---

### Task 3: Build PollRegistry with Minimal Proxy

**Files:**
- Create: `codes/contracts/contracts/PollRegistry.sol`
- Create: `codes/contracts/test/PollRegistry.test.ts`

- [ ] **Step 1: Write PollRegistry test (TDD)**

```typescript
import { expect } from "chai";
import { ethers } from "hardhat";
import { ZeroAddress } from "ethers";

describe("PollRegistry", function () {
    let registry: any;
    let semaphore: any;
    let deployer: any;
    let other: any;
    let mockImpl: any;

    beforeEach(async function () {
        [deployer, other] = await ethers.getSigners();

        // Deploy Semaphore stack (same as existing tests)
        const PoseidonT3 = await ethers.getContractFactory("PoseidonT3");
        const poseidonT3 = await PoseidonT3.deploy();

        const MockVerifier = await ethers.getContractFactory("MockSemaphoreVerifier");
        const verifier = await MockVerifier.deploy();

        const Semaphore = await ethers.getContractFactory("Semaphore", {
            libraries: {
                "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress(),
            },
        });
        semaphore = await Semaphore.deploy(await verifier.getAddress());

        // Deploy ZkAnonVoting implementation (to be used as the clone source)
        const ZkAnonVoting = await ethers.getContractFactory("ZkAnonVoting");
        mockImpl = await ZkAnonVoting.deploy();

        // Deploy PollRegistry
        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        registry = await PollRegistry.deploy();
    });

    describe("Module management", function () {
        it("Should allow owner to register a module implementation", async function () {
            await registry.registerModule("anon-vote", await mockImpl.getAddress());
            const addr = await registry.getModuleImpl("anon-vote");
            expect(addr).to.equal(await mockImpl.getAddress());
        });

        it("Should reject non-owner registering a module", async function () {
            await expect(
                registry.connect(other).registerModule("anon-vote", await mockImpl.getAddress())
            ).to.be.revertedWith("Not owner");
        });

        it("Should reject registering zero address implementation", async function () {
            await expect(
                registry.registerModule("anon-vote", ZeroAddress)
            ).to.be.revertedWith("Zero address");
        });
    });

    describe("Poll creation", function () {
        beforeEach(async function () {
            await registry.registerModule("anon-vote", await mockImpl.getAddress());
        });

        it("Should create a poll and return its address", async function () {
            const initData = mockImpl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                deployer.address,
                ["Option A", "Option B"],
            ]);

            const tx = await registry.createPoll(
                "anon-vote",
                "Best framework?",
                "Vote for your favorite",
                initData
            );
            const receipt = await tx.wait();

            const pollCount = await registry.getPollCount();
            expect(pollCount).to.equal(1);
        });

        it("Should reject creating poll with unregistered module", async function () {
            await expect(
                registry.createPoll("unknown-module", "Title", "Desc", "0x")
            ).to.be.revertedWith("Module not registered");
        });

        it("Should list all created polls", async function () {
            const initData = mockImpl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                deployer.address,
                ["A", "B"],
            ]);

            await registry.createPoll("anon-vote", "Poll 1", "Desc 1", initData);
            await registry.createPoll("anon-vote", "Poll 2", "Desc 2", initData);

            const polls = await registry.getAllPolls();
            expect(polls.length).to.equal(2);
            expect(polls[0].title).to.equal("Poll 1");
            expect(polls[1].title).to.equal("Poll 2");
        });
    });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd codes/contracts && npx hardhat test test/PollRegistry.test.ts`
Expected: FAIL -- `PollRegistry` contract does not exist yet

- [ ] **Step 3: Write PollRegistry contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";

/// @title PollRegistry - Factory and registry for all voting modules
/// @notice Creates poll instances as EIP-1167 minimal proxies. Other projects
///         integrate by calling this single contract.
contract PollRegistry {
    using Clones for address;

    struct PollInfo {
        address pollAddress;
        string moduleType;
        string title;
        string description;
        address creator;
        uint256 createdAt;
    }

    address public owner;
    PollInfo[] public polls;
    mapping(string => address) public moduleImpls;

    event ModuleRegistered(string moduleType, address implementation);
    event PollCreated(
        uint256 indexed pollId,
        address pollAddress,
        string moduleType,
        string title,
        address creator
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Register a new module implementation that can be cloned.
    /// @param moduleType A string key like "anon-vote", "blind-live", "blind-sealed".
    /// @param implementation The deployed implementation contract to clone from.
    function registerModule(string calldata moduleType, address implementation) external onlyOwner {
        require(implementation != address(0), "Zero address");
        moduleImpls[moduleType] = implementation;
        emit ModuleRegistered(moduleType, implementation);
    }

    /// @notice Returns the implementation address for a module type.
    function getModuleImpl(string calldata moduleType) external view returns (address) {
        return moduleImpls[moduleType];
    }

    /// @notice Create a new poll by cloning a registered module implementation.
    /// @param moduleType The module to clone (must be registered).
    /// @param title Human-readable poll title.
    /// @param description Human-readable poll description.
    /// @param initData ABI-encoded call to the clone's initialize() function.
    /// @return pollAddress The address of the newly created poll clone.
    function createPoll(
        string calldata moduleType,
        string calldata title,
        string calldata description,
        bytes calldata initData
    ) external returns (address pollAddress) {
        address impl = moduleImpls[moduleType];
        require(impl != address(0), "Module not registered");

        pollAddress = impl.clone();

        // Initialize the clone
        (bool success, ) = pollAddress.call(initData);
        require(success, "Initialization failed");

        polls.push(PollInfo({
            pollAddress: pollAddress,
            moduleType: moduleType,
            title: title,
            description: description,
            creator: msg.sender,
            createdAt: block.timestamp
        }));

        emit PollCreated(polls.length - 1, pollAddress, moduleType, title, msg.sender);
    }

    /// @notice Returns the total number of polls created.
    function getPollCount() external view returns (uint256) {
        return polls.length;
    }

    /// @notice Returns all polls.
    function getAllPolls() external view returns (PollInfo[] memory) {
        return polls;
    }
}
```

- [ ] **Step 4: Install OpenZeppelin (needed for Clones.sol)**

Run: `cd codes/contracts && npm install @openzeppelin/contracts`

- [ ] **Step 5: Compile**

Run: `cd codes/contracts && npx hardhat compile`
Expected: Compilation successful

- [ ] **Step 6: Run tests (will fail -- ZkAnonVoting not yet written)**

Run: `cd codes/contracts && npx hardhat test test/PollRegistry.test.ts`
Expected: FAIL -- `ZkAnonVoting` contract does not exist yet. This is expected. We write it in the next task.

- [ ] **Step 7: Commit PollRegistry (tests will pass after Task 4)**

```bash
git add codes/contracts/contracts/PollRegistry.sol codes/contracts/test/PollRegistry.test.ts
git commit -m "feat: add PollRegistry factory with EIP-1167 minimal proxy cloning"
```

---

### Task 4: Refactor ZkVoting into ZkAnonVoting (M1)

**Files:**
- Create: `codes/contracts/contracts/ZkAnonVoting.sol`
- Create: `codes/contracts/test/ZkAnonVoting.test.ts`

This is the core refactor: take the existing `ZkVoting.sol` and make it:
1. Implement `IZkPoll`
2. Use `initialize()` instead of `constructor()` (required for minimal proxy pattern)
3. Add `verifyParticipation()` for M3 receipts

- [ ] **Step 1: Write ZkAnonVoting test**

```typescript
import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as crypto from "crypto";

describe("ZkAnonVoting", function () {
    let semaphore: any;
    let voting: any;
    let deployer: any;
    let other: any;
    let identities: Identity[];

    beforeEach(async function () {
        [deployer, other] = await ethers.getSigners();

        // Deploy Semaphore stack
        const PoseidonT3 = await ethers.getContractFactory("PoseidonT3");
        const poseidonT3 = await PoseidonT3.deploy();

        const MockVerifier = await ethers.getContractFactory("MockSemaphoreVerifier");
        const verifier = await MockVerifier.deploy();

        const Semaphore = await ethers.getContractFactory("Semaphore", {
            libraries: {
                "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress(),
            },
        });
        semaphore = await Semaphore.deploy(await verifier.getAddress());

        // Deploy ZkAnonVoting implementation
        const ZkAnonVoting = await ethers.getContractFactory("ZkAnonVoting");
        const impl = await ZkAnonVoting.deploy();

        // Clone it (simulating what PollRegistry does)
        const cloneAddress = await impl.getAddress(); // For simplicity, use impl directly
        voting = await ethers.getContractAt("ZkAnonVoting", cloneAddress);

        // Initialize
        await voting.initialize(
            await semaphore.getAddress(),
            deployer.address,
            ["Option A", "Option B", "Option C"]
        );

        // Generate test identities
        identities = Array.from({ length: 3 }, () =>
            new Identity(crypto.randomBytes(32).toString("hex"))
        );
    });

    describe("IZkPoll compliance", function () {
        it("Should return Registration state initially", async function () {
            expect(await voting.getState()).to.equal(0); // Registration
        });

        it("Should return options via getOptions()", async function () {
            const opts = await voting.getOptions();
            expect(opts).to.deep.equal(["Option A", "Option B", "Option C"]);
        });

        it("Should return 0 participants initially", async function () {
            expect(await voting.getParticipantCount()).to.equal(0);
        });

        it("Should return owner address", async function () {
            expect(await voting.owner()).to.equal(deployer.address);
        });

        it("Should return empty results initially", async function () {
            const results = await voting.getResults();
            expect(results.length).to.equal(3);
            expect(results[0]).to.equal(0n);
        });
    });

    describe("Registration", function () {
        it("Should register voters and increment participant count", async function () {
            const commitments = identities.map(id => id.commitment);
            await voting.registerVoters(commitments);
            expect(await voting.getParticipantCount()).to.equal(3);
        });

        it("Should reject non-owner registration", async function () {
            await expect(
                voting.connect(other).registerVoters([identities[0].commitment])
            ).to.be.revertedWith("Not owner");
        });

        it("Should reject duplicate commitment", async function () {
            await voting.registerVoters([identities[0].commitment]);
            await expect(
                voting.registerVoters([identities[0].commitment])
            ).to.be.revertedWith("Already registered");
        });
    });

    describe("Voting", function () {
        beforeEach(async function () {
            const commitments = identities.map(id => id.commitment);
            await voting.registerVoters(commitments);
            await voting.startVoting();
        });

        it("Should transition to Voting state", async function () {
            expect(await voting.getState()).to.equal(1); // Voting
        });

        it("Should cast vote with mock proof and update tally", async function () {
            const optionIndex = 1;
            const mockProof = {
                merkleTreeDepth: 20,
                merkleTreeRoot: 0,
                nullifier: identities[0].commitment,
                message: optionIndex,
                scope: await voting.getAddress(),
                points: [0, 0, 0, 0, 0, 0, 0, 0],
            };

            await expect(voting.castVote(optionIndex, mockProof))
                .to.emit(voting, "VoteCast")
                .withArgs(optionIndex);

            const results = await voting.getResults();
            expect(results[1]).to.equal(1n);
        });

        it("Should reject double voting (same nullifier)", async function () {
            const mockProof = {
                merkleTreeDepth: 20,
                merkleTreeRoot: 0,
                nullifier: identities[0].commitment,
                message: 0,
                scope: await voting.getAddress(),
                points: [0, 0, 0, 0, 0, 0, 0, 0],
            };

            await voting.castVote(0, mockProof);
            await expect(voting.castVote(0, mockProof))
                .to.be.revertedWith("You have already voted");
        });

        it("Should reject invalid option index", async function () {
            const mockProof = {
                merkleTreeDepth: 20,
                merkleTreeRoot: 0,
                nullifier: identities[0].commitment,
                message: 99,
                scope: await voting.getAddress(),
                points: [0, 0, 0, 0, 0, 0, 0, 0],
            };

            await expect(voting.castVote(99, mockProof))
                .to.be.revertedWith("Invalid option index");
        });
    });

    describe("Participation verification (M3)", function () {
        it("Should verify participation after voting", async function () {
            const commitments = identities.map(id => id.commitment);
            await voting.registerVoters(commitments);
            await voting.startVoting();

            const nullifier = identities[0].commitment;
            const mockProof = {
                merkleTreeDepth: 20,
                merkleTreeRoot: 0,
                nullifier: nullifier,
                message: 0,
                scope: await voting.getAddress(),
                points: [0, 0, 0, 0, 0, 0, 0, 0],
            };

            await voting.castVote(0, mockProof);
            expect(await voting.verifyParticipation(nullifier)).to.be.true;
        });

        it("Should return false for unused nullifier", async function () {
            expect(await voting.verifyParticipation(12345)).to.be.false;
        });
    });

    describe("State transitions", function () {
        it("Should require at least 2 options to start voting", async function () {
            const ZkAnonVoting = await ethers.getContractFactory("ZkAnonVoting");
            const singleOpt = await ZkAnonVoting.deploy();
            await singleOpt.initialize(
                await semaphore.getAddress(),
                deployer.address,
                ["Only one"]
            );
            await expect(singleOpt.startVoting()).to.be.revertedWith("Need at least 2 options");
        });

        it("Should reject voting in Registration phase", async function () {
            const mockProof = {
                merkleTreeDepth: 20,
                merkleTreeRoot: 0,
                nullifier: 1,
                message: 0,
                scope: await voting.getAddress(),
                points: [0, 0, 0, 0, 0, 0, 0, 0],
            };
            await expect(voting.castVote(0, mockProof))
                .to.be.revertedWith("Not in voting phase");
        });

        it("Should prevent double initialization", async function () {
            await expect(
                voting.initialize(await semaphore.getAddress(), deployer.address, ["A", "B"])
            ).to.be.revertedWith("Already initialized");
        });
    });

    describe("Admin controls", function () {
        it("Should allow owner to add options during registration", async function () {
            await voting.addOption("Option D");
            const opts = await voting.getOptions();
            expect(opts.length).to.equal(4);
            expect(opts[3]).to.equal("Option D");
        });

        it("Should reject adding options after registration phase", async function () {
            await voting.registerVoters([identities[0].commitment]);
            await voting.startVoting();
            await expect(voting.addOption("Too late"))
                .to.be.revertedWith("Not in registration phase");
        });
    });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd codes/contracts && npx hardhat test test/ZkAnonVoting.test.ts`
Expected: FAIL -- `ZkAnonVoting` contract does not exist yet

- [ ] **Step 3: Write ZkAnonVoting contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "./interfaces/IZkPoll.sol";

/// @title ZkAnonVoting - Anonymous token-based voting (Module M1)
/// @notice Voters register ZK identity commitments and cast votes via
///         Semaphore proofs. Voter identity is fully anonymous. Live tally
///         is visible but individual votes are untraceable.
/// @dev Designed for EIP-1167 minimal proxy pattern. Use initialize() instead
///      of constructor. Implements IZkPoll for registry compatibility.
contract ZkAnonVoting is IZkPoll {
    ISemaphore public semaphore;
    uint256 public groupId;
    PollState public state;
    address public override owner;
    bool private _initialized;

    string[] public options;
    uint256 public participantCount;

    mapping(uint256 => bool) public isNullifierUsed;
    mapping(uint256 => bool) public registeredCommitments;
    mapping(uint256 => uint256) public voteCounts;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 optionIndex);
    event OptionAdded(string label);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Initialize the poll clone. Called once by PollRegistry after cloning.
    /// @param _semaphoreAddress Address of the deployed Semaphore contract.
    /// @param _owner The poll creator who controls registration and phase transitions.
    /// @param _initialOptions The starting set of poll options.
    function initialize(
        address _semaphoreAddress,
        address _owner,
        string[] memory _initialOptions
    ) external {
        require(!_initialized, "Already initialized");
        _initialized = true;

        semaphore = ISemaphore(_semaphoreAddress);
        owner = _owner;
        state = PollState.Registration;

        for (uint256 i = 0; i < _initialOptions.length; i++) {
            options.push(_initialOptions[i]);
        }

        groupId = semaphore.createGroup();
    }

    // ──────────────── IZkPoll Implementation ────────────────

    function getState() external view override returns (PollState) {
        return state;
    }

    function getResults() external view override returns (uint256[] memory) {
        uint256[] memory results = new uint256[](options.length);
        for (uint256 i = 0; i < options.length; i++) {
            results[i] = voteCounts[i];
        }
        return results;
    }

    function getOptions() external view override returns (string[] memory) {
        return options;
    }

    function getParticipantCount() external view override returns (uint256) {
        return participantCount;
    }

    function verifyParticipation(uint256 nullifierHash) external view override returns (bool) {
        return isNullifierUsed[nullifierHash];
    }

    // ──────────────── Admin Functions ────────────────

    function addOption(string calldata label) external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");
        options.push(label);
        emit OptionAdded(label);
    }

    function registerVoter(uint256 identityCommitment) external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");
        require(!registeredCommitments[identityCommitment], "Already registered");
        registeredCommitments[identityCommitment] = true;
        semaphore.addMember(groupId, identityCommitment);
        participantCount++;
        emit VoterRegistered(identityCommitment);
    }

    function registerVoters(uint256[] calldata identityCommitments) external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");
        for (uint256 i = 0; i < identityCommitments.length; i++) {
            require(!registeredCommitments[identityCommitments[i]], "Already registered");
            registeredCommitments[identityCommitments[i]] = true;
            semaphore.addMember(groupId, identityCommitments[i]);
            participantCount++;
            emit VoterRegistered(identityCommitments[i]);
        }
    }

    function startVoting() external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");
        require(options.length >= 2, "Need at least 2 options");
        state = PollState.Voting;
        emit StateChanged(PollState.Voting);
    }

    function endVoting() external onlyOwner {
        require(state == PollState.Voting, "Not in voting phase");
        state = PollState.Ended;
        emit StateChanged(PollState.Ended);
    }

    // ──────────────── Voter Functions ────────────────

    function castVote(
        uint256 vote,
        ISemaphore.SemaphoreProof calldata proof
    ) external {
        require(state == PollState.Voting, "Not in voting phase");
        require(vote < options.length, "Invalid option index");
        require(!isNullifierUsed[proof.nullifier], "You have already voted");
        require(proof.scope == uint256(uint160(address(this))), "Invalid scope");
        require(proof.message == vote, "Tampered vote signal");

        semaphore.verifyProof(groupId, proof);

        isNullifierUsed[proof.nullifier] = true;
        voteCounts[vote]++;

        emit VoteCast(vote);
    }
}
```

- [ ] **Step 4: Compile**

Run: `cd codes/contracts && npx hardhat compile`
Expected: Compilation successful

- [ ] **Step 5: Run ZkAnonVoting tests**

Run: `cd codes/contracts && npx hardhat test test/ZkAnonVoting.test.ts`
Expected: All tests pass

- [ ] **Step 6: Run PollRegistry tests (should pass now)**

Run: `cd codes/contracts && npx hardhat test test/PollRegistry.test.ts`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add codes/contracts/contracts/ZkAnonVoting.sol codes/contracts/test/ZkAnonVoting.test.ts
git commit -m "feat: add ZkAnonVoting (M1) implementing IZkPoll with initialize pattern"
```

---

### Task 5: Update Deploy Script for New Architecture

**Files:**
- Modify: `codes/contracts/scripts/deploy.ts`

- [ ] **Step 1: Rewrite deploy script**

```typescript
import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with:", deployer.address);

    // 1. Deploy Poseidon library
    const PoseidonT3 = await ethers.getContractFactory("PoseidonT3");
    const poseidonT3 = await PoseidonT3.deploy();
    console.log("PoseidonT3:", await poseidonT3.getAddress());

    // 2. Deploy Semaphore verifier (mock for local, real for testnet)
    const VerifierFactory = await ethers.getContractFactory("MockSemaphoreVerifier");
    const verifier = await VerifierFactory.deploy();
    console.log("SemaphoreVerifier:", await verifier.getAddress());

    // 3. Deploy Semaphore core
    const SemaphoreFactory = await ethers.getContractFactory("Semaphore", {
        libraries: {
            "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress(),
        },
    });
    const semaphore = await SemaphoreFactory.deploy(await verifier.getAddress());
    const semaphoreAddress = await semaphore.getAddress();
    console.log("Semaphore:", semaphoreAddress);

    // 4. Deploy PollRegistry
    const PollRegistryFactory = await ethers.getContractFactory("PollRegistry");
    const registry = await PollRegistryFactory.deploy();
    const registryAddress = await registry.getAddress();
    console.log("PollRegistry:", registryAddress);

    // 5. Deploy ZkAnonVoting implementation (clone source)
    const ZkAnonVotingFactory = await ethers.getContractFactory("ZkAnonVoting");
    const anonVotingImpl = await ZkAnonVotingFactory.deploy();
    const anonVotingImplAddress = await anonVotingImpl.getAddress();
    console.log("ZkAnonVoting (impl):", anonVotingImplAddress);

    // 6. Register module in registry
    await registry.registerModule("anon-vote", anonVotingImplAddress);
    console.log('Registered module: "anon-vote"');

    // 7. Deploy ZkAirdrop (unchanged)
    const claimAmount = ethers.parseEther("1.0");
    const ZkAirdropFactory = await ethers.getContractFactory("ZkAirdrop");
    const zkAirdrop = await ZkAirdropFactory.deploy(semaphoreAddress, claimAmount);
    console.log("ZkAirdrop:", await zkAirdrop.getAddress());

    const fundTx = await deployer.sendTransaction({
        to: await zkAirdrop.getAddress(),
        value: ethers.parseEther("10.0"),
    });
    await fundTx.wait();
    console.log("ZkAirdrop funded with 10 ETH");

    // 8. Write addresses to frontend
    const frontendSrcDir = path.join(__dirname, "../../frontend/src");
    if (fs.existsSync(frontendSrcDir)) {
        const addressMap = {
            REGISTRY_ADDRESS: registryAddress,
            SEMAPHORE_ADDRESS: semaphoreAddress,
            ANON_VOTING_IMPL: anonVotingImplAddress,
            AIRDROP_ADDRESS: await zkAirdrop.getAddress(),
        };
        fs.writeFileSync(
            path.join(frontendSrcDir, "deployed-addresses.json"),
            JSON.stringify(addressMap, null, 2)
        );
        console.log("Saved addresses to frontend/src/deployed-addresses.json");
    }

    console.log("\n=== Deployment complete ===");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
```

- [ ] **Step 2: Test deployment on local node**

Run (in separate terminal or use existing podman node):
```bash
cd codes/contracts && npx hardhat run scripts/deploy.ts --network localhost
```
Expected: All contracts deploy, addresses printed, `deployed-addresses.json` updated

- [ ] **Step 3: Commit**

```bash
git add codes/contracts/scripts/deploy.ts
git commit -m "refactor: update deploy script for PollRegistry architecture"
```

---

### Task 6: Copy ABIs to Frontend

**Files:**
- Create: `codes/frontend/src/abi/IZkPoll.json`
- Create: `codes/frontend/src/abi/PollRegistry.json`
- Create: `codes/frontend/src/abi/ZkAnonVoting.json`
- Modify: `codes/frontend/src/config.ts`
- Delete: `codes/frontend/src/ZkVoting.json`
- Delete: `codes/frontend/src/ZkVotingFactory.json`
- Delete: `codes/frontend/src/ZkVotingLottery.json`

- [ ] **Step 1: Create ABI extraction script**

After compiling contracts, ABIs live in `codes/contracts/artifacts/`. Create a small script to copy them:

```typescript
// codes/contracts/scripts/copyAbis.ts
import fs from "fs";
import path from "path";

const artifacts = path.join(__dirname, "../artifacts/contracts");
const frontendAbi = path.join(__dirname, "../../frontend/src/abi");

if (!fs.existsSync(frontendAbi)) {
    fs.mkdirSync(frontendAbi, { recursive: true });
}

const contracts = [
    { artifact: "interfaces/IZkPoll.sol/IZkPoll.json", output: "IZkPoll.json" },
    { artifact: "PollRegistry.sol/PollRegistry.json", output: "PollRegistry.json" },
    { artifact: "ZkAnonVoting.sol/ZkAnonVoting.json", output: "ZkAnonVoting.json" },
];

for (const c of contracts) {
    const src = path.join(artifacts, c.artifact);
    const data = JSON.parse(fs.readFileSync(src, "utf-8"));
    fs.writeFileSync(
        path.join(frontendAbi, c.output),
        JSON.stringify({ abi: data.abi }, null, 2)
    );
    console.log(`Copied ${c.output}`);
}
```

- [ ] **Step 2: Run it**

Run: `cd codes/contracts && npx hardhat compile && npx ts-node scripts/copyAbis.ts`
Expected: Three ABI files created in `frontend/src/abi/`

- [ ] **Step 3: Update config.ts**

```typescript
import { http, createConfig } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { metaMask, mock } from 'wagmi/connectors'
import deployedAddresses from './deployed-addresses.json'

const RPC_URL = import.meta.env.VITE_RPC_URL || 'http://127.0.0.1:8545'

export const config = createConfig({
    chains: [hardhat, localhost],
    connectors: [
        metaMask(),
        mock({
            accounts: [
                '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
            ],
        }),
    ],
    transports: {
        [hardhat.id]: http(RPC_URL),
        [localhost.id]: http(RPC_URL),
    },
})

export const REGISTRY_ADDRESS = deployedAddresses.REGISTRY_ADDRESS as `0x${string}`;
export const SEMAPHORE_ADDRESS = deployedAddresses.SEMAPHORE_ADDRESS as `0x${string}`;
export const AIRDROP_ADDRESS = deployedAddresses.AIRDROP_ADDRESS as `0x${string}`;
```

- [ ] **Step 4: Delete old ABI files**

```bash
rm codes/frontend/src/ZkVoting.json codes/frontend/src/ZkVotingFactory.json codes/frontend/src/ZkVotingLottery.json
```

- [ ] **Step 5: Commit**

```bash
git add codes/contracts/scripts/copyAbis.ts codes/frontend/src/abi/ codes/frontend/src/config.ts
git rm codes/frontend/src/ZkVoting.json codes/frontend/src/ZkVotingFactory.json codes/frontend/src/ZkVotingLottery.json
git commit -m "refactor: migrate frontend ABIs to abi/ directory, update config for Registry"
```

---

## Phase 1: Frontend Refactor

### Task 7: Create Frontend Hooks

**Files:**
- Create: `codes/frontend/src/hooks/useRegistry.ts`
- Create: `codes/frontend/src/hooks/usePoll.ts`

- [ ] **Step 1: Write useRegistry hook**

```typescript
// codes/frontend/src/hooks/useRegistry.ts
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { REGISTRY_ADDRESS } from '../config'
import PollRegistryABI from '../abi/PollRegistry.json'

export interface PollInfo {
    pollAddress: string;
    moduleType: string;
    title: string;
    description: string;
    creator: string;
    createdAt: bigint;
}

export function useAllPolls() {
    return useReadContract({
        address: REGISTRY_ADDRESS,
        abi: PollRegistryABI.abi,
        functionName: 'getAllPolls',
        query: { refetchInterval: 5000 },
    })
}

export function useCreatePoll() {
    const { data: hash, mutateAsync, isPending } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

    async function createPoll(
        moduleType: string,
        title: string,
        description: string,
        initData: `0x${string}`
    ) {
        return mutateAsync({
            address: REGISTRY_ADDRESS,
            abi: PollRegistryABI.abi,
            functionName: 'createPoll',
            args: [moduleType, title, description, initData],
        })
    }

    return { createPoll, isPending, isConfirming, isSuccess, hash }
}
```

- [ ] **Step 2: Write usePoll hook**

```typescript
// codes/frontend/src/hooks/usePoll.ts
import { useReadContract, useWriteContract, useWaitForTransactionReceipt, usePublicClient } from 'wagmi'
import { useState, useEffect } from 'react'
import IZkPollABI from '../abi/IZkPoll.json'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'

export function usePollState(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'getState',
        query: { refetchInterval: 2000 },
    })
}

export function usePollOptions(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'getOptions',
        query: { refetchInterval: 5000 },
    })
}

export function usePollResults(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'getResults',
        query: { refetchInterval: 3000 },
    })
}

export function usePollOwner(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'owner',
    })
}

export function useParticipantCount(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'getParticipantCount',
        query: { refetchInterval: 3000 },
    })
}

export function useVerifyParticipation(pollAddress: `0x${string}`, nullifierHash: bigint | undefined) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'verifyParticipation',
        args: nullifierHash !== undefined ? [nullifierHash] : undefined,
        query: { enabled: nullifierHash !== undefined },
    })
}

export function usePollWrite() {
    const { data: hash, mutateAsync, isPending } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })
    return { mutateAsync, isPending, isConfirming, isSuccess, hash }
}
```

- [ ] **Step 3: Commit**

```bash
git add codes/frontend/src/hooks/useRegistry.ts codes/frontend/src/hooks/usePoll.ts
git commit -m "feat: add useRegistry and usePoll React hooks for IZkPoll interface"
```

---

### Task 8: Refactor Home Page

**Files:**
- Modify: `codes/frontend/src/pages/Home.tsx`

- [ ] **Step 1: Rewrite Home.tsx to use Registry hooks**

```tsx
// codes/frontend/src/pages/Home.tsx
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { encodeFunctionData } from 'viem'
import { useAllPolls, useCreatePoll } from '../hooks/useRegistry'
import { SEMAPHORE_ADDRESS } from '../config'
import { useAccount } from 'wagmi'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'

export default function Home() {
    const { address } = useAccount()
    const { data: polls } = useAllPolls()
    const { createPoll, isPending, isConfirming, isSuccess } = useCreatePoll()

    const [title, setTitle] = useState('')
    const [description, setDescription] = useState('')
    const [options, setOptions] = useState<string[]>(['', ''])

    function updateOption(index: number, value: string) {
        const next = [...options]
        next[index] = value
        setOptions(next)
    }

    function addOption() {
        setOptions([...options, ''])
    }

    function removeOption(index: number) {
        if (options.length <= 2) return
        setOptions(options.filter((_, i) => i !== index))
    }

    async function handleCreatePoll(e: React.FormEvent) {
        e.preventDefault()
        if (!address) return

        const validOptions = options.filter(o => o.trim() !== '')
        if (validOptions.length < 2) return

        const initData = encodeFunctionData({
            abi: ZkAnonVotingABI.abi,
            functionName: 'initialize',
            args: [SEMAPHORE_ADDRESS, address, validOptions],
        })

        await createPoll('anon-vote', title, description, initData as `0x${string}`)
        setTitle('')
        setDescription('')
        setOptions(['', ''])
    }

    const pollList = (polls as any[]) || []

    return (
        <div className="max-w-6xl mx-auto p-6">
            {/* Create Poll Form */}
            <section className="mb-12 bg-white rounded-xl shadow p-6">
                <h2 className="text-2xl font-bold mb-4">Create New Poll</h2>
                <form onSubmit={handleCreatePoll} className="space-y-4">
                    <input
                        type="text"
                        placeholder="Poll title"
                        value={title}
                        onChange={e => setTitle(e.target.value)}
                        className="w-full border rounded-lg px-4 py-2"
                        required
                    />
                    <input
                        type="text"
                        placeholder="Description"
                        value={description}
                        onChange={e => setDescription(e.target.value)}
                        className="w-full border rounded-lg px-4 py-2"
                    />
                    <div className="space-y-2">
                        <label className="font-medium">Options</label>
                        {options.map((opt, i) => (
                            <div key={i} className="flex gap-2">
                                <input
                                    type="text"
                                    placeholder={`Option ${i + 1}`}
                                    value={opt}
                                    onChange={e => updateOption(i, e.target.value)}
                                    className="flex-1 border rounded-lg px-4 py-2"
                                    required
                                />
                                {options.length > 2 && (
                                    <button type="button" onClick={() => removeOption(i)}
                                        className="text-red-500 px-2">Remove</button>
                                )}
                            </div>
                        ))}
                        <button type="button" onClick={addOption}
                            className="text-blue-600 text-sm">+ Add option</button>
                    </div>
                    <button type="submit" disabled={isPending || isConfirming}
                        className="bg-blue-600 text-white px-6 py-2 rounded-lg disabled:opacity-50">
                        {isPending ? 'Confirm in wallet...' : isConfirming ? 'Creating...' : 'Create Poll'}
                    </button>
                    {isSuccess && <p className="text-green-600">Poll created!</p>}
                </form>
            </section>

            {/* Poll List */}
            <section>
                <h2 className="text-2xl font-bold mb-4">Active Polls</h2>
                {pollList.length === 0 ? (
                    <p className="text-gray-500">No polls yet. Create one above.</p>
                ) : (
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                        {[...pollList].reverse().map((poll: any, i: number) => (
                            <Link key={i} to={`/poll/${poll.pollAddress}`}
                                className="block bg-white rounded-xl shadow p-4 hover:shadow-lg transition">
                                <h3 className="font-bold text-lg">{poll.title}</h3>
                                <p className="text-gray-600 text-sm mb-2">{poll.description}</p>
                                <p className="text-xs text-gray-400 font-mono truncate">{poll.pollAddress}</p>
                                <span className="inline-block mt-2 text-xs bg-blue-100 text-blue-700 px-2 py-1 rounded">
                                    {poll.moduleType}
                                </span>
                            </Link>
                        ))}
                    </div>
                )}
            </section>
        </div>
    )
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd codes/frontend && npx tsc --noEmit`
Expected: No type errors

- [ ] **Step 3: Commit**

```bash
git add codes/frontend/src/pages/Home.tsx
git commit -m "refactor: rewrite Home page to use PollRegistry hooks"
```

---

### Task 9: Refactor Poll Page

**Files:**
- Modify: `codes/frontend/src/pages/Poll.tsx`

- [ ] **Step 1: Rewrite Poll.tsx to use IZkPoll hooks**

```tsx
// codes/frontend/src/pages/Poll.tsx
import { useState, useEffect } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useAccount, usePublicClient } from 'wagmi'
import { parseAbiItem } from 'viem'
import { Identity } from '@semaphore-protocol/identity'
import { Group } from '@semaphore-protocol/group'
import { generateProof } from '@semaphore-protocol/proof'
import {
    usePollState, usePollOptions, usePollResults,
    usePollOwner, useParticipantCount, usePollWrite
} from '../hooks/usePoll'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'

let group: Group | null = null;
let isGroupSynced = false;

function loadSavedIdentity(pollAddr: string | undefined): Identity | null {
    if (!pollAddr) return null;
    const saved = localStorage.getItem(`semaphore-identity-${pollAddr}`);
    return saved ? new Identity(saved) : null;
}

export default function Poll() {
    const { address: pollAddress } = useParams<{ address: string }>()
    const { address: userAddress } = useAccount()
    const publicClient = usePublicClient()

    const typedPollAddr = pollAddress as `0x${string}`

    const { data: pollState } = usePollState(typedPollAddr)
    const { data: optionsData, refetch: refetchOptions } = usePollOptions(typedPollAddr)
    const { data: resultsData } = usePollResults(typedPollAddr)
    const { data: pollOwner } = usePollOwner(typedPollAddr)
    const { data: participantCount } = useParticipantCount(typedPollAddr)
    const { mutateAsync: writeContract, isPending, isConfirming } = usePollWrite()

    const [localIdentity, setLocalIdentity] = useState<Identity | null>(null)
    const [selectedOption, setSelectedOption] = useState(0)
    const [statusMsg, setStatusMsg] = useState('')
    const [inviteToken, setInviteToken] = useState('')
    const [tokenCount, setTokenCount] = useState(5)
    const [generatedTokens, setGeneratedTokens] = useState<string[]>([])
    const [newOptionLabel, setNewOptionLabel] = useState('')

    const pollOptions = (optionsData as string[]) || []
    const results = (resultsData as bigint[]) || []
    const isOwner = userAddress && pollOwner && userAddress.toLowerCase() === (pollOwner as string).toLowerCase()
    const stateNum = Number(pollState ?? 0)
    const stateLabels = ['Registration', 'Voting', 'Ended']

    useEffect(() => {
        setLocalIdentity(loadSavedIdentity(pollAddress))
        isGroupSynced = false
    }, [pollAddress])

    async function syncGroupState() {
        if (!publicClient || !pollAddress) return
        const logs = await publicClient.getLogs({
            address: typedPollAddr,
            event: parseAbiItem('event VoterRegistered(uint256 identityCommitment)'),
            fromBlock: 0n,
        })
        group = new Group()
        for (const log of logs) {
            const commitment = (log as any).args.identityCommitment
            group.addMember(commitment)
        }
        isGroupSynced = true
    }

    function loadIdentityFromToken() {
        if (!inviteToken.trim() || !pollAddress) return
        const identity = new Identity(inviteToken.trim())
        localStorage.setItem(`semaphore-identity-${pollAddress}`, inviteToken.trim())
        setLocalIdentity(identity)
        setStatusMsg('Identity loaded from token.')
    }

    async function handleGenerateTokens() {
        if (!pollAddress) return
        const tokens: string[] = []
        const commitments: bigint[] = []
        for (let i = 0; i < tokenCount; i++) {
            const secret = Array.from(crypto.getRandomValues(new Uint8Array(32)))
                .map(b => b.toString(16).padStart(2, '0')).join('')
            const id = new Identity(secret)
            tokens.push(secret)
            commitments.push(id.commitment)
        }
        await writeContract({
            address: typedPollAddr,
            abi: ZkAnonVotingABI.abi,
            functionName: 'registerVoters',
            args: [commitments],
        })
        setGeneratedTokens(tokens)
        isGroupSynced = false
        setStatusMsg(`Generated ${tokenCount} tokens and registered on-chain.`)
    }

    async function handleVote() {
        if (!localIdentity || !pollAddress) return
        setStatusMsg('Syncing group...')
        await syncGroupState()
        if (!group) { setStatusMsg('Failed to sync group.'); return }

        const memberIndex = group.indexOf(localIdentity.commitment)
        if (memberIndex === -1) { setStatusMsg('Your identity is not registered.'); return }

        setStatusMsg('Generating ZK proof...')
        const proof = await generateProof(localIdentity, group, selectedOption, pollAddress)

        setStatusMsg('Submitting vote...')
        await writeContract({
            address: typedPollAddr,
            abi: ZkAnonVotingABI.abi,
            functionName: 'castVote',
            args: [selectedOption, proof],
        })

        localStorage.setItem(`voted-${pollAddress}`, proof.nullifier.toString())
        setStatusMsg('Vote cast successfully!')
    }

    async function handleStartVoting() {
        await writeContract({
            address: typedPollAddr,
            abi: ZkAnonVotingABI.abi,
            functionName: 'startVoting',
        })
    }

    async function handleEndVoting() {
        await writeContract({
            address: typedPollAddr,
            abi: ZkAnonVotingABI.abi,
            functionName: 'endVoting',
        })
    }

    async function handleAddOption() {
        if (!newOptionLabel.trim()) return
        await writeContract({
            address: typedPollAddr,
            abi: ZkAnonVotingABI.abi,
            functionName: 'addOption',
            args: [newOptionLabel.trim()],
        })
        setNewOptionLabel('')
        refetchOptions()
    }

    const optionColors = [
        'bg-blue-500', 'bg-indigo-400', 'bg-emerald-500', 'bg-amber-500',
        'bg-rose-500', 'bg-purple-500', 'bg-teal-500', 'bg-orange-500',
    ]
    const totalVotes = results.reduce((sum, v) => sum + Number(v), 0)

    return (
        <div className="max-w-6xl mx-auto p-6">
            <Link to="/" className="text-blue-600 text-sm mb-4 inline-block">&larr; Back to polls</Link>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* Left: Voter Actions */}
                <div className="space-y-6">
                    {/* State Badge */}
                    <div className="bg-white rounded-xl shadow p-4">
                        <div className="flex items-center gap-3">
                            <span className={`px-3 py-1 rounded-full text-sm font-medium text-white ${
                                stateNum === 0 ? 'bg-yellow-500' : stateNum === 1 ? 'bg-green-500' : 'bg-gray-500'
                            }`}>{stateLabels[stateNum]}</span>
                            <span className="text-sm text-gray-500">{Number(participantCount ?? 0)} registered</span>
                        </div>
                    </div>

                    {/* Identity */}
                    <div className="bg-white rounded-xl shadow p-4">
                        <h3 className="font-bold mb-3">Your Identity</h3>
                        {localIdentity ? (
                            <p className="text-green-600 text-sm">Identity ready. You can vote when voting opens.</p>
                        ) : (
                            <div className="space-y-2">
                                <input type="text" placeholder="Paste your invite token"
                                    value={inviteToken} onChange={e => setInviteToken(e.target.value)}
                                    className="w-full border rounded-lg px-4 py-2 text-sm font-mono" />
                                <button onClick={loadIdentityFromToken}
                                    className="bg-blue-600 text-white px-4 py-2 rounded-lg text-sm">
                                    Load Identity
                                </button>
                            </div>
                        )}
                    </div>

                    {/* Voting */}
                    {stateNum === 1 && localIdentity && (
                        <div className="bg-white rounded-xl shadow p-4">
                            <h3 className="font-bold mb-3">Cast Your Vote</h3>
                            <div className="space-y-2 mb-4">
                                {pollOptions.map((opt, i) => (
                                    <button key={i}
                                        onClick={() => setSelectedOption(i)}
                                        className={`w-full text-left px-4 py-3 rounded-lg border-2 transition ${
                                            selectedOption === i ? 'border-blue-500 bg-blue-50' : 'border-gray-200 hover:border-gray-300'
                                        }`}>
                                        {opt}
                                    </button>
                                ))}
                            </div>
                            <button onClick={handleVote} disabled={isPending || isConfirming}
                                className="w-full bg-blue-600 text-white py-3 rounded-lg font-medium disabled:opacity-50">
                                {isPending ? 'Confirm in wallet...' : isConfirming ? 'Submitting...' : 'Generate Proof & Vote'}
                            </button>
                        </div>
                    )}

                    {statusMsg && (
                        <div className="bg-gray-50 rounded-lg p-3 text-sm">{statusMsg}</div>
                    )}
                </div>

                {/* Right: Results + Admin */}
                <div className="space-y-6">
                    {/* Results */}
                    <div className="bg-white rounded-xl shadow p-4">
                        <h3 className="font-bold mb-3">Results {totalVotes > 0 && `(${totalVotes} votes)`}</h3>
                        <div className="space-y-3">
                            {pollOptions.map((opt, i) => {
                                const count = Number(results[i] ?? 0)
                                const pct = totalVotes > 0 ? (count / totalVotes) * 100 : 0
                                return (
                                    <div key={i}>
                                        <div className="flex justify-between text-sm mb-1">
                                            <span>{opt}</span>
                                            <span className="font-medium">{count} ({pct.toFixed(1)}%)</span>
                                        </div>
                                        <div className="w-full bg-gray-200 rounded-full h-3">
                                            <div className={`${optionColors[i % optionColors.length]} h-3 rounded-full transition-all`}
                                                style={{ width: `${pct}%` }} />
                                        </div>
                                    </div>
                                )
                            })}
                        </div>
                    </div>

                    {/* Admin Controls */}
                    {isOwner && (
                        <div className="bg-white rounded-xl shadow p-4">
                            <h3 className="font-bold mb-3">Admin Controls</h3>
                            <div className="space-y-3">
                                {stateNum === 0 && (
                                    <>
                                        <button onClick={handleStartVoting}
                                            className="w-full bg-green-600 text-white py-2 rounded-lg">
                                            Start Voting
                                        </button>
                                        <div className="flex gap-2">
                                            <input type="text" placeholder="New option"
                                                value={newOptionLabel} onChange={e => setNewOptionLabel(e.target.value)}
                                                className="flex-1 border rounded-lg px-3 py-2 text-sm" />
                                            <button onClick={handleAddOption}
                                                className="bg-gray-200 px-4 py-2 rounded-lg text-sm">Add</button>
                                        </div>
                                        <div className="border-t pt-3">
                                            <label className="text-sm font-medium">Generate Invite Tokens</label>
                                            <div className="flex gap-2 mt-1">
                                                <input type="number" min={1} max={100} value={tokenCount}
                                                    onChange={e => setTokenCount(Number(e.target.value))}
                                                    className="w-20 border rounded-lg px-3 py-2 text-sm" />
                                                <button onClick={handleGenerateTokens}
                                                    className="bg-indigo-600 text-white px-4 py-2 rounded-lg text-sm">
                                                    Generate
                                                </button>
                                            </div>
                                            {generatedTokens.length > 0 && (
                                                <div className="mt-2 space-y-1">
                                                    {generatedTokens.map((t, i) => (
                                                        <div key={i} className="text-xs font-mono bg-gray-50 p-2 rounded cursor-pointer hover:bg-gray-100"
                                                            onClick={() => navigator.clipboard.writeText(t)}>
                                                            Voter {i + 1}: {t.slice(0, 16)}... (click to copy)
                                                        </div>
                                                    ))}
                                                </div>
                                            )}
                                        </div>
                                    </>
                                )}
                                {stateNum === 1 && (
                                    <button onClick={handleEndVoting}
                                        className="w-full bg-red-600 text-white py-2 rounded-lg">
                                        End Voting
                                    </button>
                                )}
                            </div>
                        </div>
                    )}
                </div>
            </div>
        </div>
    )
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd codes/frontend && npx tsc --noEmit`
Expected: No type errors

- [ ] **Step 3: Commit**

```bash
git add codes/frontend/src/pages/Poll.tsx
git commit -m "refactor: rewrite Poll page to use IZkPoll hooks and ZkAnonVoting"
```

---

### Task 10: Clean Up Old Contracts and Run Full Test Suite

**Files:**
- Delete: `codes/contracts/contracts/ZkVoting.sol`
- Delete: `codes/contracts/contracts/ZkVotingFactory.sol`
- Delete: `codes/contracts/test/ZkVotingTokenFlow.ts`

- [ ] **Step 1: Delete old files**

```bash
rm codes/contracts/contracts/ZkVoting.sol codes/contracts/contracts/ZkVotingFactory.sol codes/contracts/test/ZkVotingTokenFlow.ts
```

- [ ] **Step 2: Run all contract tests**

Run: `cd codes/contracts && npx hardhat test`
Expected: All tests in `PollRegistry.test.ts` and `ZkAnonVoting.test.ts` pass

- [ ] **Step 3: Run deployment to verify full stack**

Run: `cd codes/contracts && npx hardhat node` (in background)
Then: `cd codes/contracts && npx hardhat run scripts/deploy.ts --network localhost`
Expected: All contracts deploy successfully, addresses printed

- [ ] **Step 4: Commit cleanup**

```bash
git rm codes/contracts/contracts/ZkVoting.sol codes/contracts/contracts/ZkVotingFactory.sol codes/contracts/test/ZkVotingTokenFlow.ts
git commit -m "refactor: remove legacy ZkVoting and ZkVotingFactory contracts"
```

---

### Task 11: Rebuild and Verify Demo

**Files:**
- Modify: `codes/contracts/docker-entrypoint.sh` (update for new deploy script)
- Modify: `codes/frontend/src/deployed-addresses.json`

- [ ] **Step 1: Update docker-entrypoint.sh**

Replace the deploy section to match the new deploy script output format:

```bash
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
```

- [ ] **Step 2: Rebuild containers**

Run:
```bash
cd codes && podman compose build --podman-build-args="--security-opt=seccomp=unconfined"
podman compose up -d
```

- [ ] **Step 3: Verify demo is accessible**

Run:
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:5173/
curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://localhost:8545/
```
Expected: 200 for frontend, JSON response for RPC

- [ ] **Step 4: Commit**

```bash
git add codes/contracts/docker-entrypoint.sh
git commit -m "chore: update docker-entrypoint for new deployment architecture"
```

---

### Task 12: Write Architecture Documentation

**Files:**
- Create: `docs/architecture/system-overview.md`
- Create: `docs/architecture/module-m1-anon-voting.md`

- [ ] **Step 1: Write system overview**

```markdown
# System Architecture Overview

## Contract Architecture

The system uses a modular contract architecture with a central registry.

### PollRegistry (Factory)
- **Address:** Deployed once per network. All integrations start here.
- **Role:** Creates poll instances as EIP-1167 minimal proxies. Maintains a list of all polls.
- **Module types:** `"anon-vote"` (M1), `"blind-live"` (M2a, future), `"blind-sealed"` (M2b, future)
- **Key functions:**
  - `registerModule(moduleType, implementation)` -- owner registers a new module
  - `createPoll(moduleType, title, description, initData)` -- anyone creates a poll
  - `getAllPolls()` -- returns all polls with metadata

### IZkPoll (Interface)
- **Role:** Shared interface that all voting modules implement.
- **Key functions:**
  - `getState()` -- poll lifecycle state (Registration/Voting/Ended)
  - `getResults()` -- vote tally per option
  - `getOptions()` -- poll option labels
  - `getParticipantCount()` -- number of registered participants
  - `verifyParticipation(nullifierHash)` -- M3 receipt verification
  - `owner()` -- poll creator address

### Minimal Proxy Pattern (EIP-1167)
Each poll is a thin clone (~45 bytes of bytecode) that delegates all calls to a deployed implementation contract. This saves gas: creating a poll costs ~45k gas instead of ~2M+ gas for a full contract deployment.

The implementation contract is deployed once per module type. Clones are created by `PollRegistry.createPoll()` and initialized via `initialize()`.

## Frontend Architecture

### Hooks
- `useRegistry` -- reads polls from PollRegistry, creates polls
- `usePoll` -- reads poll state/results/options via IZkPoll interface

### Pages
- `/` (Home) -- create polls, browse active polls
- `/poll/:address` -- vote on a poll, view results, admin controls

### Identity Management
- Semaphore identity stored in localStorage per poll address
- Admin generates invite tokens (random secrets) and registers commitments on-chain
- Voters paste invite token to derive their identity
```

- [ ] **Step 2: Write M1 module doc**

```markdown
# Module M1: Anonymous Token Voting (ZkAnonVoting)

## Privacy Dimensions
- **Identity:** anonymous (ZK proof, no address link)
- **Content:** public-aggregate (live tally, individual votes untraceable)
- **Temporality:** immediate

## How It Works

1. **Registration:** Admin generates invite tokens (random secrets). Each token derives a Semaphore identity commitment. Commitments are registered on-chain in a Semaphore group.

2. **Voting:** Voter pastes their invite token in the UI. The frontend derives the identity, syncs the Semaphore group from on-chain events, generates a ZK proof ("I am a member of this group, voting for option X"), and submits it to the contract.

3. **Verification:** Contract verifies the ZK proof, checks the nullifier hasn't been used before, and increments the vote count for the selected option.

4. **Participation Receipt:** After voting, the nullifier hash serves as a receipt. Anyone can call `verifyParticipation(nullifierHash)` to confirm a vote was cast with that nullifier, without learning who cast it.

## Contract: ZkAnonVoting.sol

### State Machine
```
Registration --> Voting --> Ended
```

### Security Properties
- **Anonymity:** Votes are linked to nullifiers, not addresses.
- **Double-vote prevention:** Each nullifier can only be used once.
- **Scope binding:** Proof scope = contract address, preventing replay across polls.
- **Vote integrity:** Proof message = option index, preventing vote tampering.

### Known Limitations
- Admin must register voters (centralized registration).
- Small group deanonymization: if 5 voters and 4 voted "Yes," the 5th is identified by elimination.
- MockSemaphoreVerifier used in local tests -- real verifier required for production.
```

- [ ] **Step 3: Commit**

```bash
git add docs/architecture/system-overview.md docs/architecture/module-m1-anon-voting.md
git commit -m "docs: add system architecture overview and M1 module documentation"
```

---

## Phase 2-6: High-Level Outline

These phases are outlined but not detailed here. Each will get its own implementation plan when the previous phase's stability gate passes.

### Phase 2: M2a (Blind Voting -- Live Tally)
- Create `ZkBlindLiveVoting.sol` implementing `IZkPoll`
- Simplified crypto: votes stored encrypted, poll creator decrypts aggregate at end
- Register as `"blind-live"` module in PollRegistry
- Frontend: mode selector on poll creation, encrypted vote submission UI
- Test: professor's "handsome vote" scenario end-to-end

### Phase 3: M2b (Blind Voting -- Sealed)
- Create `ZkBlindSealedVoting.sol` implementing `IZkPoll`
- Commit-reveal with keccak256, threshold + time-lock triggers
- Voter timeout handling (grace period, then excluded)
- Frontend: sealed mode indicator, reveal phase UI

### Phase 4: Participation Receipts (M3)
- `verifyParticipation()` already on IZkPoll (implemented in Phase 1)
- Frontend: generate downloadable JSON receipt after voting
- Frontend: standalone `/verify` page to check receipts
- Test: round-trip receipt verification for M1 and M2

### Phase 5: Integration Layer
- `@zk-poll/sdk` npm package wrapping contract calls
- Integration guide documentation
- Example project that imports SDK and creates a verified poll

### Phase 6: Testnet Deployment
- Deploy to Sepolia or Amoy
- Network switching in frontend
- Gas optimization pass
- Replace MockSemaphoreVerifier with real verifier
