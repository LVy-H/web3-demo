# Versioning

> **Status: PROPOSAL.** Discuss with your collaborator before adopting. Mark sections you accept; replace ones you don't.

This project ships two things that need to stay coordinated: **smart contracts** (immutable once deployed) and **the frontend** (mutable, deployed continuously). The versioning scheme has to handle both.

## TL;DR

- **Repo:** semver tags on the git repo for releases (`v0.2.0`).
- **Contracts:** an *implementation* version is the git tag at which the contract was compiled and deployed. The *deployed instance* is identified by its address, captured in `deployed-addresses.<network>.json` per network.
- **Frontend:** semver, same tag as the repo.
- **ABIs:** copied from compiled artifacts at release time, committed under `codes/frontend/src/abi/`. The version is the repo tag they came from.

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
| Hardhat (local) | `codes/frontend/src/deployed-addresses.json` (overwritten per `npm run deploy:local`) |
| Sepolia (future) | `codes/frontend/src/deployed-addresses.sepolia.json` (committed) |
| Mainnet (future) | `codes/frontend/src/deployed-addresses.mainnet.json` (committed, multisig-owned) |

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

## Frontend versioning

Same tag as the repo. The frontend bundle should display the version somewhere (footer or about page) so users know what they're running.

`package.json` `version` field tracks the latest released version. Bump it as part of the release commit.

## ABI versioning

ABIs in `codes/frontend/src/abi/*.json` are copied from `codes/contracts/artifacts/` at release time. They must be regenerated and re-copied any time a contract changes.

Workflow:
1. Change a contract.
2. `npm run compile` in `codes/contracts/`.
3. Re-copy ABIs into `codes/frontend/src/abi/` (consider adding a `npm run copy-abis` script — currently exists per `package.json` but the script file may be missing; verify).
4. Test the frontend against the new ABI before tagging.

## What we don't do

- **No upgrade proxies** for voting modules. Polls are immutable per the EIP-1167 design. If you need to change behavior, deploy a new module impl and register it for new polls.
- **No off-chain version negotiation.** The frontend reads the contract address from `deployed-addresses.<network>.json` and assumes ABI compatibility per the committed ABI files. If you change a deployed contract's storage layout or function set, you must bump the repo and redeploy.
