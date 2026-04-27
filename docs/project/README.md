# Project

Lifecycle, governance, and operational docs. Distinct from `architecture/` (what is) and `improvements/` (what to fix) — this directory is **how we run the project**.

## Files

| File | Purpose | Update cadence |
|------|---------|----------------|
| [STATUS.md](./STATUS.md) | Snapshot of where the project is right now: shipped, in flight, blocked. | Weekly, or after every merge that changes scope. |
| [ROADMAP.md](./ROADMAP.md) | Phased long-term direction. What we plan to build, in what order, and why. | Quarterly, or whenever phase boundaries move. |
| [FOCUS.md](./FOCUS.md) | What we're working on **this iteration**. Smaller scope than ROADMAP. The thing to look at on Monday morning. | Per iteration (1–2 weeks). |
| [VERSIONING.md](./VERSIONING.md) | How versions work for contracts, frontend, ABIs. | When the scheme changes (rare). |
| [RELEASING.md](./RELEASING.md) | Step-by-step release process: tag → deploy → record addresses → update changelog. | When the process changes. |
| [CHANGELOG.md](./CHANGELOG.md) | What changed in each release, in human-readable form. | Every release. |

## Reading order

- **First time on the project:** STATUS → ROADMAP → FOCUS, in that order. You'll know the present, the future, and the now.
- **Coming back after a break:** STATUS + CHANGELOG. What's different since you left.
- **About to ship a release:** RELEASING + VERSIONING.
- **Wondering what to work on:** FOCUS, then `improvements/findings.md`.

## Boundary with other doc directories

| If your update is about... | It belongs in... |
|---|---|
| What the system *does* (a contract behavior, a hook contract) | `architecture/` |
| A bug, missing test, or stale doc | `improvements/findings.md` |
| Coding/UX rules contributors must follow | `standards/` |
| What we're building **next** or **why** we built X | `project/` (here) |
| Historical record of how something was originally designed | `archive/` |
