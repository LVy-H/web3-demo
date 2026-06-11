# Module M2: Blind Voting (ZkBlindVoting)

## Privacy Dimensions
- **Identity:** pseudonymous (voter's wallet address is public; registration is permissionless)
- **Content:** sealed-during-voting (commit-reveal — votes are hidden until the reveal window)
- **Temporality:** delayed (results only visible after reveal phase)

> M2 differs from M1: it provides **vote secrecy in time** (nobody can see how you voted while the poll is running) but does **not** unlink your identity from your vote — once you reveal, your address is associated with your choice on-chain.

## How It Works

1. **Registration:** Anyone calls `register()` to add their wallet address to the voter list. Permissionless — no admin gate. One address = one vote.

2. **Voting (commit phase):** Voter selects an option, generates a random 32-byte salt locally, and submits `commitVote(keccak256(abi.encodePacked(optionIndex, salt)))`. The contract stores only the hash. The frontend stores `(optionIndex, salt)` in localStorage so the voter can reveal later.

3. **Voting closes → reveal window opens:** Owner calls `endVoting()`. This sets `revealDeadline = block.timestamp + revealDuration` and transitions to `Ended`. Reveals only accepted while `block.timestamp <= revealDeadline`.

4. **Reveal:** Each voter calls `revealVote(optionIndex, salt)`. Contract recomputes the hash, checks it matches the commit, and increments the vote count for that option. **Unrevealed votes are silently dropped** — losing your salt or skipping reveal = vote lost.

5. **Finalization:** After the deadline passes, owner calls `finalizeResults()`. This sets `resultsFinalized = true` and emits `ResultsFinalized`. (Currently this is a marker only — results are computed continuously as reveals happen; finalization just signals the end of the window.)

## Contract: ZkBlindVoting.sol

### State Machine
```
Registration ──startVoting()──> Voting ──endVoting()──> Ended ──finalizeResults()──> Ended (finalized)
     │                            │                       │
     ├── register() (anyone)      ├── commitVote()        ├── revealVote()  (during reveal window)
     ├── addOption() (owner)      │                       └── finalizeResults() (after deadline)
     └── startVoting() (owner)    └── endVoting() (owner)
```

### Initialization (Minimal Proxy Pattern)
```solidity
function initialize(
    address _owner,
    string[] memory _initialOptions,
    uint256 _revealDuration,  // seconds — how long the reveal window stays open
    uint8 _resultsPolicy          // R4: 0 = sealed-until-close (default), 1 = live-public
) external
```
A `_initialized` guard prevents double initialization. **Note:** unlike M1, there is no Semaphore dependency — M2 doesn't use ZK proofs.

### Key Functions

| Function | Access | Phase | Description |
|----------|--------|-------|-------------|
| `initialize()` | Once only | -- | Set up the poll clone |
| `register()` | Anyone | Registration | Register caller's address as a voter |
| `addOption()` | Owner | Registration | Add a new poll option |
| `startVoting()` | Owner | Registration | Transition to Voting (requires ≥2 options AND ≥1 voter) |
| `commitVote(commitHash)` | Registered voter | Voting | Submit `keccak256(abi.encodePacked(optionIndex, salt))` |
| `endVoting()` | Owner | Voting | Transition to Ended, set reveal deadline |
| `revealVote(optionIndex, salt)` | Anyone w/ commit | Ended (before deadline) | Reveal a previously committed vote |
| `finalizeResults()` | Owner | Ended (after deadline) | Lock the poll |
| `getState()` | Anyone | Any | Current lifecycle state |
| `getResults()` | Anyone | Any | Vote tallies (only revealed votes count) |
| `getOptions()` | Anyone | Any | Option labels array |
| `getParticipantCount()` | Anyone | Any | Number of registered voters |
| `getRevealDeadline()` | Anyone | Any | Unix timestamp when reveal window closes |
| `hasVoted(addr)` | Anyone | Any | Whether an address has committed a vote |
| `hasRevealed(addr)` | Anyone | Any | Whether an address has revealed |
| `verifyParticipation(nullifierHash)` | Anyone | Any | IZkPoll compat — interprets the uint256 as `address(uint160(nullifierHash))` and returns whether that address has committed |

### Security Properties
- **Vote secrecy in time:** Choices are hidden until reveal phase. An attacker reading the chain during voting sees only commit hashes.
- **One vote per address:** `commits[msg.sender].commitHash != bytes32(0)` check prevents double-commits.
- **Hash binding:** `revealVote` requires `keccak256(abi.encodePacked(optionIndex, salt)) == commits[msg.sender].commitHash`, so reveals can't be lied about.
- **Reveal deadline:** Late reveals are rejected. Hard window prevents the result-tampering vector where voters wait to see partial reveals before deciding to reveal their own.

### Known Limitations
- **Identity is public:** The voter list (`getVoters()`) and per-vote `VoteRevealed(address voter, uint256 optionIndex)` events make votes traceable to addresses post-reveal. This is fundamental to the commit-reveal scheme — for full anonymity use M1.
- **Sybil-prone:** Anyone can register; one address = one vote, but addresses are cheap. Use M1 if you need a curated voter list.
- **Lost-salt = lost vote:** Salt + option index are kept in localStorage only. Browser data clearing or device switch = the vote can never be revealed.
- **Reveal deadline is monotonic:** Once set by `endVoting()`, the deadline cannot be extended. If your voters need more time, you have to deploy a new poll.
- **`finalizeResults()` is informational:** Results are tallied continuously during the reveal window. The finalization step is just a marker; off-chain consumers should still trust `getResults()` after the deadline.
