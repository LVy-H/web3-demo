# Tessera Server

The self-hosted server for Tessera: a verifiable bulletin board for group
decisions.

It owns the durable state for a Tessera instance:

- SQLite append-only ballot log.
- Convener/admin-token authentication.
- Decision lifecycle routes.
- Open-ballot casts with idempotency and signed receipts.
- Secret-ballot credential issuance with RFC 9474 RSABSSA blind signatures.
- RFC 6962 Merkle roots/checkpoints.
- Broadcast anchor bundle.
- Public read API and independent verifier.

## Develop

```bash
npm install
npm test
npm run dev      # ts-node src/index.ts (PORT=3001)
npm run build    # tsc -> dist/
npm start        # node dist/index.js
```

The local one-command product demo is run from the repository root:

```bash
./demo.sh up
```

## Useful Endpoints

- `GET /health`
- `GET /key`
- `POST /decisions` with `Authorization: Bearer <admin-token>`
- `POST /decisions/:id/open`
- `POST /decisions/:id/close`
- `POST /decisions/:id/publish`
- `POST /register`
- `POST /ballots`
- `GET /decisions/:id`
- `GET /ballots?decisionId=...`
- `GET /root?decisionId=...`
- `GET /results?decisionId=...`
- `GET /anchor?decisionId=...`
- `GET /verify/:id`

Design reference:
`../../docs/superpowers/specs/2026-06-19-tessera-system-design.md`.
