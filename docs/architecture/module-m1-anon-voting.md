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
     │               │
     ├── addOption()  ├── castVote()
     ├── registerVoter()
     └── registerVoters()
```

### Initialization (Minimal Proxy Pattern)
Unlike a constructor, `initialize()` is called after the EIP-1167 clone is created:
```solidity
function initialize(
    address _semaphoreAddress,
    address _owner,
    string[] memory _initialOptions,
    uint8 _resultsPolicy          // R4: 0 = sealed-until-close (default), 1 = live-public
) external
```
A `_initialized` guard prevents double initialization.

### Key Functions

| Function | Access | Phase | Description |
|----------|--------|-------|-------------|
| `initialize()` | Once only | -- | Set up the poll clone |
| `registerVoter()` | Owner | Registration | Add one identity commitment |
| `registerVoters()` | Owner | Registration | Batch register commitments |
| `addOption()` | Owner | Registration | Add a new poll option |
| `startVoting()` | Owner | Registration | Transition to Voting phase |
| `endVoting()` | Owner | Voting | Transition to Ended phase |
| `castVote()` | Anyone | Voting | Submit ZK proof + vote |
| `getState()` | Anyone | Any | Current lifecycle state |
| `getResults()` | Anyone | Any | Vote tallies array |
| `getOptions()` | Anyone | Any | Option labels array |
| `getParticipantCount()` | Anyone | Any | Number of registered voters |
| `verifyParticipation()` | Anyone | Any | Check if nullifier was used |

### Security Properties
- **Anonymity:** Votes are linked to nullifiers, not addresses.
- **Double-vote prevention:** Each nullifier can only be used once.
- **Scope binding:** Proof scope = contract address, preventing replay across polls.
- **Vote integrity:** Proof message = option index, preventing vote tampering.

### Known Limitations
- Admin must register voters (centralized registration).
- Small group deanonymization: if 5 voters and 4 voted "Yes," the 5th is identified by elimination.
- MockSemaphoreVerifier used in local tests -- real verifier required for production.
- Gas costs: voters currently pay gas to submit votes, creating a potential traceability vector. Relayer integration (Phase 5+) addresses this.
- `registerVoters()` caps a single batch at **50** commitments. `Semaphore.addMember` cost grows with tree depth, so ~50 inserts (~24.5M gas) fit a 30M mainnet block while 100 (~50M) would not. Chunk larger registrations client-side into batches of ≤50 (findings P1-12 / P1-13).
