# Tessera code workspace

This directory holds the implementation behind the current Tessera architecture:
a self-hosted, verifiable bulletin-board server plus one Flutter client.

The old on-chain stack (Hardhat contracts, Semaphore/Groth16 voting modules,
gasless relayer, and browser dApp) has been removed from the working tree. It is
preserved in git history only. The default local product no longer needs a
blockchain, wallet, MetaMask, relayer, or SNARK prover.

## Components

| Path | Purpose |
| --- | --- |
| [`server/`](server/) | TypeScript/Express server: SQLite append-only ballot log, decision lifecycle, convener auth, tally/verdict, signed receipts, Merkle checkpoints, anchor, blind-signature credentials, and public verify API. |
| [`app/`](app/) | Flutter workspace: the voter, organizer, and verifier UI. The app defaults to the server-backed REST path (`SERVER_MODE=true`). |
| [`control/`](control/) | Multi-tenant operator/control plane: one isolated Tessera server per org, routed by host name. |

## Quick Start

From the repository root, run the one-command demo:

```bash
./demo.sh up
```

It starts the server on `http://127.0.0.1:3001`, builds and serves the Flutter
web app on `http://127.0.0.1:8080`, and prints the admin token used by organizer
actions. Stop it with:

```bash
./demo.sh down
```

For development, run the pieces separately:

```bash
./dev-stack.sh up
cd codes/app/apps/tessera
flutter run -d chrome
```

The app reads the default server URL from `SERVER_URL` and can be re-pointed at
runtime in Settings -> Network. Paste the admin token there to create, open,
close, and publish decisions.

## Server API at a Glance

Public/read routes:

- `GET /health`
- `GET /key`
- `GET /decisions/:id`
- `GET /decisions/:id/issuer`
- `GET /ballots?decisionId=...`
- `GET /root?decisionId=...`
- `GET /results?decisionId=...`
- `GET /anchor?decisionId=...`
- `GET /verify/:id`

Participant routes:

- `POST /register` for secret-ballot blind-signature credential issuance.
- `POST /ballots` for idempotent ballot casts and signed receipts.

Convener routes require `Authorization: Bearer <admin-token>`:

- `POST /decisions`
- `POST /decisions/:id/open`
- `POST /decisions/:id/close`
- `POST /decisions/:id/publish`
- `POST /decisions/:id/cancel`
- `POST /decisions/:id/extend`

Supported tally methods are `single`, `approval`, `ranked`, `quadratic`, and
`survey`, with `abstain` accepted for every method. Secret ballots use RFC 9474
RSABSSA blind-signature credentials so eligibility can be checked without
linking the issued credential to the eventual ballot.

## Tests

```bash
cd codes/server  && npm test
cd codes/control && npm test
cd codes/app     && dart run melos run analyze && dart run melos run test
```

## Related Docs

- [`../README.md`](../README.md) - product overview and local demo.
- [`../deploy/README.md`](../deploy/README.md) - self-hosting the server and static app.
- [`../deploy/multi-tenant/README.md`](../deploy/multi-tenant/README.md) - isolated org hosting.
- [`../docs/project/STATUS.md`](../docs/project/STATUS.md) - current project status.
- [`../docs/architecture/system-overview.md`](../docs/architecture/system-overview.md) - architecture orientation.
