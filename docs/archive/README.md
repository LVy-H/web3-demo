# Archive

Frozen historical documents from the initial build phase.

## Contents

| Path | Date | What |
|------|------|------|
| `specs/2026-04-10-anonymous-web3-system-design.md` | 2026-04-10 | Original design spec for the modular voting platform. Predates the current code; some module names changed (`blind-live` / `blind-sealed` → `blind-vote`). |
| `plans/2026-04-10-phase-0-1-foundation-and-m1.md` | 2026-04-10 | Step-by-step implementation plan for Phase 0–1 (registry + IZkPoll + M1 refactor). Written for an agentic worker. |

## Rules

- **Read-only.** Do not edit these files to match current code. Their value is the snapshot they capture.
- If something here is wrong about the system as it stands today, the fix goes in `docs/architecture/` (or a new entry in `docs/improvements/findings.md`), **not here**.
- New historical docs (post-mortems, completed migration plans) belong here once they're done. Use the same date-prefixed naming: `YYYY-MM-DD-short-slug.md`.

## Why this exists

Historical context survives even when the code moves on. When someone asks "why is this called a `moduleType` string instead of an enum?" the spec answers it. Without an archive, that answer disappears.
