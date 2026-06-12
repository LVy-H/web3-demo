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

### Run with Docker

The same stack runs containerized (`docker-compose.yml`, dev-only: loopback
ports, hardhat dev keys, ephemeral chain — every `up` is a fresh deterministic
deploy):

```bash
# Backend: chain (hardhat node -> deploy -> demo seed) + relayer
docker compose --profile dev up --build

# Whole product: backend + the Flutter web app + block explorer
docker compose --profile full up --build
# (or: ./dev-stack.sh compose --profile full up --build)

docker compose --profile full down
```

| Service  | URL                     | Profile   | Notes |
|----------|-------------------------|-----------|-------|
| chain    | `http://localhost:8545` | dev, full | Hardhat, chainId 31337; healthcheck on `eth_chainId` |
| relayer  | `http://localhost:3001` | dev, full | healthcheck on `/api/relay/info` |
| web      | `http://localhost:8080` | full      | Flutter web release via nginx (precompressed, SPA fallback) |
| explorer | `http://localhost:3728` | full      | alethio lite explorer |

Env knobs (all optional; set in the shell or a `.env` next to the compose
file):

- `SEED_DEMO` (default `1`) — seed the demo poll + demo survey after deploy.
- `USE_REAL_VERIFIER` (default off) — `true` deploys the real Groth16
  `SemaphoreVerifier` instead of the always-true mock.
- `RELAYER_PRIVATE_KEY` (default hardhat #0), `REGISTRY_ADDRESS` (default =
  the deterministic local deploy), `RELAY_RATE_LIMIT_MAX` (default `600`),
  `RELAY_CREATE_DAILY_MAX` (default `1000`) — relayer config (see
  `codes/relayer/src/config.ts`).
- `WEB_RPC_URL` / `WEB_RELAYER_URL` — **build-time** dart-defines for the web
  image; browser-facing URLs (default `http://127.0.0.1:8545` /
  `http://localhost:3001`). The hosted app can also be re-pointed at runtime
  via Settings → Network.

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
