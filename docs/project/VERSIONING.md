# Versioning

> **Status: PROPOSAL.** Discuss with your collaborator before adopting. Mark sections you accept; replace ones you don't.

This project ships two things that need to stay coordinated: **smart contracts** (immutable once deployed) and **the frontend** (mutable, deployed continuously). The versioning scheme has to handle both.

## TL;DR

- **Repo:** semver tags on the git repo for releases (`v0.2.0`).
- **Contracts:** an *implementation* version is the git tag at which the contract was compiled and deployed. The *deployed instance* is identified by its address, captured in `deployed-addresses.<network>.json` per network.
- **Client:** semver, same tag as the repo (the Tessera Flutter app, `codes/mobile/`).
- **ABIs:** generated into `codes/contracts/artifacts/` by `npm run compile`; the client and relayer encode the calls they need directly. The version is the repo tag they came from.

## Repo versioning (semver)

| Bump | When |
|------|------|
| **MAJOR** (`1.x.x → 2.0.0`) | Breaking ABI change to a deployed contract (new function signature on `IZkPoll`, removed event, changed storage layout in an upgrade) |
| **MINOR** (`0.2.x → 0.3.0`) | New module, new contract, new feature — backward-compatible at the ABI level |
| **PATCH** (`0.2.1 → 0.2.2`) | Bug fix, frontend-only change, doc update, refactor with no ABI change |

Pre-1.0 (where we are): we'll likely break things often. Use `0.x.y` and treat any minor bump as potentially breaking. Move to `1.0.0` only when:
- All contracts deployed to a public testnet
- A real (non-Mock) verifier is in use
- No P0/P1 items open

## Contract versioning

Contracts are immutable per deployment. "Versioning" therefore has two layers:

### 1. Implementation version (the code)

The git tag at which the implementation was compiled. Example: `ZkAnonVoting@v0.2.1`. Embedded in:
- The git tag on the repo
- A `string public constant VERSION = "0.2.1"` field on each contract (proposed — adopt or skip)
- The deployed-addresses ledger per network

### 2. Deployment instance (the address)

Each deployment is permanently identified by its on-chain address on a given chain. **Addresses do not change with versions** — a new code version means a new deployment, which means a new address.

| Network | Source of truth |
|---------|----------------|
| Hardhat (local) | `codes/contracts/deployed-addresses.json` (overwritten per `npm run deploy:local`) |
| Sepolia (future) | `codes/contracts/deployed-addresses.sepolia.json` (committed) |
| Mainnet (future) | `codes/contracts/deployed-addresses.mainnet.json` (committed, multisig-owned) |

Each per-network file should also include the git tag at which the contracts were deployed:
```json
{
  "version": "0.2.1",
  "commit": "abc1234",
  "deployedAt": "2026-04-27T14:32:00Z",
  "REGISTRY_ADDRESS": "0x...",
  "...": "..."
}
```

### Module-impl swaps in the Registry

`PollRegistry.registerModule(moduleType, implementation)` allows the owner to swap an implementation without redeploying the registry. **Note that this does not upgrade existing polls** — clones are immutable EIP-1167 proxies. After a swap, only newly created polls use the new impl.

A swap is therefore equivalent to a minor bump for the registry's module catalog. Document it in CHANGELOG with the old/new impl addresses.

## Client versioning

Same tag as the repo. The Tessera client (`codes/mobile/`) displays its version on the Settings screen so users know what they're running.

`codes/mobile/pubspec.yaml` (`version: X.Y.Z+N`) is the canonical client version; `codes/contracts/package.json` and `codes/relayer/package.json` track the same repo semver. Bump all three as part of the release commit.

## ABI versioning

The contract ABIs are generated into `codes/contracts/artifacts/` by `npm run compile`. The Flutter client and the relayer encode the calls they need directly, so there is no separate copied-ABI directory to keep in sync (the old `codes/frontend/src/abi/` is gone with the deleted frontend).

Workflow:
1. Change a contract.
2. `npm run compile` in `codes/contracts/`.
3. Re-run the suites that would catch an encoding mismatch: `npm test` (contracts), `npm test` (relayer), and `flutter test` (client — the cross-impl crypto/encoding tests).
4. Commit the regenerated `artifacts/` alongside the contract change before tagging.

## What we don't do

- **No upgrade proxies** for voting modules. Polls are immutable per the EIP-1167 design. If you need to change behavior, deploy a new module impl and register it for new polls.
- **No off-chain version negotiation.** The client reads the contract address from `deployed-addresses.<network>.json` and assumes ABI compatibility per the compiled artifacts. If you change a deployed contract's storage layout or function set, you must bump the repo and redeploy.
