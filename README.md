# Tessera — anonymous on-chain voting

Tessera is a modular, privacy-preserving voting platform on the **Semaphore
Protocol (v4)**, with an optional gasless/sponsored relayer. A central
`PollRegistry` factory deploys per-poll EIP-1167 minimal proxies for **six
voting modules** — anonymous, blind (commit-reveal), approval, ranked-choice,
quadratic, and survey — plus a standalone `ZkAirdrop`.

This file is the top-level index. For developer setup start at
[`codes/README.md`](codes/README.md); for the end-user / demo flow see
[`INSTRUCTIONS.md`](INSTRUCTIONS.md).

## At a glance

| Component | Path | Purpose | Docs |
| --- | --- | --- | --- |
| Contracts | [`codes/contracts/`](codes/contracts/) | Solidity + Hardhat. `PollRegistry` factory, six voting modules, `ZkAirdrop`. | [`codes/README.md`](codes/README.md) |
| Client (Tessera) | [`codes/mobile/`](codes/mobile/) | One Flutter app across **mobile, desktop, and web** — the sole client. | [`INSTRUCTIONS.md`](INSTRUCTIONS.md) |
| Relayer | [`codes/relayer/`](codes/relayer/) | Optional Express service: gasless votes + sponsored (wallet-free) poll lifecycle. | [`codes/relayer/README.md`](codes/relayer/README.md) |
| Docs | [`docs/`](docs/) | Architecture, project tracking, standards, backlog. | [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md) |

## Voting modules

| Module | Type | Ballot |
| --- | --- | --- |
| Anonymous (M1) | `anon-vote` | Semaphore group membership; one option, nullifier-protected. |
| Blind (M2) | `blind-vote` | Commit-reveal; no SNARK. |
| Approval | `approval-vote` | Multi-select bitmask — approve any number of options. |
| Ranked-choice | `ranked-vote` | Rank options; instant-runoff winner (off-chain Dart tally). |
| Quadratic | `quadratic-vote` | 100-credit budget; cost = votes². |
| Survey | `survey-vote` | Multi-question "Google-Forms"; one ballot per survey. |

## Quick start

```bash
# One-step local stack: Hardhat node -> deploy -> demo poll -> relayer
./dev-stack.sh up

# The Tessera app (voting/proving works on the web build)
cd codes/mobile && flutter run -d chrome   # or -d linux / -d <android-serial>
```

`deploy:local` writes the contract addresses to
`codes/contracts/deployed-addresses.json`, which the app reads. **No wallet is
required** for the default local flow — the app signs with a dev signer or
routes through the sponsored relayer. The full manual 4-terminal walkthrough is
in [`codes/README.md`](codes/README.md).

## Testing

```bash
cd codes/contracts && npm test     # Hardhat — 268 passing
cd codes/relayer   && npm test     # Vitest  — 96 passing (2 skipped)
cd codes/mobile    && flutter analyze && flutter test
```

CI (`.github/workflows/ci.yml`) runs all three jobs — contracts, relayer, and
mobile — on every PR to `main`. Local dev and CI use `MockSemaphoreVerifier`
(always-true), so no SNARK artifacts are needed.

## Repo layout

```
codes/
├── contracts/   Solidity + Hardhat (PollRegistry + 6 modules + ZkAirdrop, Semaphore v4)
├── mobile/      Tessera — the Flutter client (mobile / desktop / web)
└── relayer/     Express gasless-relay + sponsored-lifecycle service (optional)
docs/
├── architecture/  System overview + per-module deep dives
├── project/       Status, roadmap, changelog, releasing, versioning
└── improvements/  Backlog (findings + status board)
```

## Security notes

This repo is a teaching / demonstration project. Before any production use,
review:

- Contract assumptions and verifier wiring — [`codes/README.md`](codes/README.md).
- Relayer trust model and production checklist —
  [`codes/relayer/README.md`](codes/relayer/README.md).
- System-wide threat model —
  [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md).

Public-network deployment requires the **real Groth16 `SemaphoreVerifier`**
(not the local mock) and is gated on the Phase 10 testnet milestone; see
[`docs/improvements/findings.md`](docs/improvements/findings.md) (`P4-23` /
`P4-24`).
