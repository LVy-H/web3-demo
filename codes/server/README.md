# Tessera Server

The self-hosted server for Tessera — a verifiable bulletin board for group decisions.
See the design at `docs/superpowers/specs/2026-06-19-tessera-system-design.md` and the
plan at `docs/superpowers/plans/2026-06-19-tessera-1.0-implementation-plan.md`.

**Status:** skeleton (Phase 1, Task 1.1). Only `GET /health` exists so far. The
append-only ballot log, decision lifecycle, eligibility + blind-signature credential
issuer, Merkle checkpoints, the anchor adapter, and the public read/verifier API land in
Phases 2–3.

## Develop

```bash
npm install
npm test        # vitest
npm run dev     # ts-node src/index.ts (PORT=3001)
npm run build   # tsc -> dist/
```
