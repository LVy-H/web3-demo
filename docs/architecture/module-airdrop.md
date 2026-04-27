# ZkAirdrop (Standalone)

## Status

**Standalone contract — NOT registered in `PollRegistry`.** Deployed once by the deploy script, funded with ETH, and exists independently. No clones, no factory.

## Privacy Dimensions
- **Identity:** anonymous (claim is unlinkable from registration via Semaphore ZK proof)
- **Content:** N/A (no choices — single-action claim)
- **Temporality:** immediate (claim → ETH transferred in same tx)

## How It Works

1. **Registration:** Anyone calls `registerMember(identityCommitment)` with their Semaphore commitment. This is **permissionless** — no whitelist, no admin gate.

2. **Owner closes registration:** Owner calls `startAirdrop()`. State transitions from `Registration` to `Claiming`. No more registrations accepted.

3. **Claim:** A registered member generates a Semaphore proof binding `(receiver address)` as the message and `address(this)` as the scope, then calls `claimAirdrop(receiver, proof)`. Contract:
   - Verifies the proof is valid for the registered group.
   - Checks `proof.scope == address(this)` (replay protection across airdrops).
   - Checks `proof.message == uint256(uint160(receiver))` (binds claim to receiver).
   - Checks the nullifier hasn't been used (one claim per identity).
   - Transfers `airdropAmount` ETH to `receiver`.

The receiver address can be **completely disconnected** from the address that originally registered — that's the whole point. You register from Address A, claim to Address B, and the on-chain link between them is cryptographically hidden.

## Contract: ZkAirdrop.sol

### State Machine
```
Registration ──startAirdrop()──> Claiming
     │                              │
     ├── registerMember() (anyone)  └── claimAirdrop(receiver, proof) (anyone w/ valid proof)
     └── startAirdrop() (owner)
```

There is no terminal state. Once in `Claiming`, the contract stays there forever (see Known Limitations).

### Initialization (Constructor — NOT a clone)
Unlike voting modules, `ZkAirdrop` uses a real constructor and is deployed directly:
```solidity
constructor(address _semaphoreAddress, uint256 _airdropAmount)
```
The constructor calls `semaphore.createGroup(address(this))` and stores the resulting `groupId`.

### Key Functions

| Function | Access | Phase | Description |
|----------|--------|-------|-------------|
| `registerMember(uint256 identityCommitment)` | Anyone | Registration | Add commitment to the Semaphore group |
| `startAirdrop()` | Owner | Registration | Close registration, open claims |
| `claimAirdrop(address receiver, SemaphoreProof proof)` | Anyone w/ proof | Claiming | Verify proof, send ETH to receiver |
| `receive()` | Anyone | Any | Accept ETH deposits (top up the pool) |

### Security Properties
- **Anonymity:** Claim is unlinkable from registration. Receiver address is bound by `proof.message`; an observer cannot tell which registered identity corresponds to which payout.
- **Replay protection:** `proof.scope == address(this)` prevents reusing a proof against a different airdrop contract.
- **One claim per identity:** Nullifier mapping (`isNullifierUsed`) ensures each Semaphore identity can only claim once.
- **Receiver binding:** `proof.message == uint256(uint160(receiver))` prevents an observer from front-running the claim with a different receiver.
- **Checks-effects-interactions:** Nullifier is marked used **before** the ETH transfer, preventing reentrancy from re-claiming. (No `ReentrancyGuard` is used — see [P1-8](../improvements/findings.md#p1-8) for hardening.)

### Known Limitations
- **Permissionless registration with no cap:** Anyone can register before `startAirdrop()` is called. This is by design (open airdrops are usually intentional), but it means a sybil with N identities can drain `N * airdropAmount` of ETH. Sybil resistance is the operator's responsibility — pair with off-chain proof-of-personhood or whitelist enforcement before launch.
- **No escape hatch for unclaimed ETH:** If some registered members never claim, their share is stuck forever. No `recoverUnclaimed()` for the owner. See [P1-9](../improvements/findings.md#p1-9).
- **No claim deadline:** The `Claiming` state is terminal. There's no way to close claims and recover the pool.
- **No `ReentrancyGuard`:** Defensive depth-in-defense missing. State ordering is correct, so no known exploit, but add a guard for safety. See [P1-8](../improvements/findings.md#p1-8).
- **No tests:** This contract has zero test coverage as of writing — see [P0-3](../improvements/findings.md#p0-3).
- **Pragma drift:** Declares `^0.8.23` while voting contracts declare `^0.8.20`; project compiles all with `0.8.34`. See [P1-10](../improvements/findings.md#p1-10).
