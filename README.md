# Anonymous Web3 Voting & Airdrop

ZK voting (anonymous + blind) and ZK airdrop on Semaphore Protocol v4, with
optional gasless relay.

The canonical architectural doc lives at
[`codes/README.md`](codes/README.md). This file is a top-level index — read
it to find your way around, then jump into the module READMEs.

## At a glance

| Module    | Path                                     | Purpose                                                                                | Docs                                                                       |
| --------- | ---------------------------------------- | -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Contracts | [`codes/contracts/`](codes/contracts/)   | Solidity + Hardhat. `PollRegistry` factory, M1 anon voting, M2 blind voting, ZK airdrop. | [`codes/README.md`](codes/README.md)                                       |
| Frontend  | [`codes/frontend/`](codes/frontend/)     | React 19 + Vite + Wagmi. Direct-wallet and relayer voting UI. Playwright E2E.          | [`codes/frontend/README.md`](codes/frontend/README.md)                     |
| Relayer   | [`codes/relayer/`](codes/relayer/)       | Optional Express service for gasless vote / claim submission.                          | [`codes/relayer/README.md`](codes/relayer/README.md)                       |
| Docs      | [`docs/architecture/`](docs/architecture/) | System overview + per-module deep dives.                                               | [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md) |

## Quick start

```bash
# 1. Clone (already done if you are reading this).
git clone <repo-url> && cd <repo>

# 2. Contracts: install, start local node, deploy.
cd codes/contracts && npm install
npm run node           # leave running in its own terminal
npm run deploy:local   # in a second terminal; writes addresses for the frontend

# 3. Frontend: install, run dev server on http://localhost:5173.
cd ../frontend && npm install && npm run dev
```

`deploy:local` writes the contract addresses to
`codes/frontend/src/deployed-addresses.json`, which the dev server picks up
automatically. Full multi-terminal walkthrough and MetaMask setup live in
[`codes/README.md`](codes/README.md). End-user / demo-runner flow is in
[`INSTRUCTIONS.md`](INSTRUCTIONS.md).

## Optional: gasless voting

[`codes/relayer/`](codes/relayer/) is an Express service that submits ZK votes
and airdrop claims on behalf of voters — the voter still generates the proof
client-side, but pays no gas and needs no wallet. The relayer is off by
default; when it is not running, the frontend uses direct wallet submission.
Trust model, API, and production checklist: [`codes/relayer/README.md`](codes/relayer/README.md).

## Testing

### Contract tests

```bash
cd codes/contracts && npm test
```

Hardhat + Chai. Uses `MockSemaphoreVerifier` so no SNARK artifacts need to be
downloaded.

### Frontend E2E (Playwright, demo-video capture)

```bash
cd codes/frontend
npm run test:e2e:install   # one-time: install Chromium
npm run test:e2e:record    # headed run + HTML report
```

Videos for every test land under `codes/frontend/test-results/<test-name>/video.webm`
(see `codes/frontend/playwright.config.ts`). The E2E suite expects a running
Hardhat node, deployed contracts, and the dev server — same prerequisites as
the Quick start above.

## Repo layout

```
codes/
├── contracts/    Solidity + Hardhat (Semaphore v4 + custom errors + OZ Initializable/Ownable)
├── frontend/     React 19 + Vite + Wagmi (Direct + Relayer voting + Playwright E2E)
└── relayer/      Express.js gasless relay service (optional)
docs/
└── architecture/ Design docs (system overview + M1/M2/airdrop deep dives)
```

## Security notes

This repo is a teaching / demonstration project. Before any production use,
review the per-module security sections:

- Contract assumptions and verifier wiring — [`codes/README.md`](codes/README.md).
- Relayer trust model and production checklist —
  [`codes/relayer/README.md`](codes/relayer/README.md) (see "Production
  checklist").
- System-wide threat model — [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md).
