# Documentation

Living references for **Tessera** — the modular zero-knowledge voting platform (`codes/`).

## Structure

```
docs/
├── README.md                  ← you are here
├── architecture/              What the system IS today (per-contract reference)
│   ├── system-overview.md     Top-level: registry, clones, IZkPoll, deploy stack
│   ├── module-m1-anon-voting.md   ZkAnonVoting (Semaphore-based ZK voting)
│   ├── module-m2-blind-voting.md  ZkBlindVoting (commit-reveal)
│   ├── module-approval.md         ZkApprovalVoting (multi-select bitmask)
│   ├── module-ranked.md           ZkRankedVoting (ranked-choice / IRV)
│   ├── module-quadratic.md        ZkQuadraticVoting (credit budget, Σv²≤100)
│   ├── module-survey.md           ZkSurveyVoting (multi-question survey)
│   └── module-airdrop.md          ZkAirdrop (standalone, not in registry)
├── framework/                 Conceptual frameworks shared across modules
│   ├── privacy-dimensions.md  3-axis privacy model (identity / content / temporality)
│   └── module-comparison.md   Which module fits which use case
├── standards/                 Coding & UX rules every PR must follow
│   ├── client-conventions.md  Flutter/Dart conventions for codes/mobile
│   ├── ux-design-principles.md
│   └── visual-design-guide.md
├── project/                   Project lifecycle & operations
│   ├── README.md              Index for this directory
│   ├── STATUS.md              Snapshot of where we are right now
│   ├── ROADMAP.md             Phased long-term direction
│   ├── FOCUS.md               This iteration's goal + active work items
│   ├── VERSIONING.md          How versions work (proposal)
│   ├── RELEASING.md           Release process per network (proposal)
│   └── CHANGELOG.md           What changed in each release
├── improvements/              Active issue tracker (this is where work happens)
│   ├── README.md              Status board
│   ├── architecture-context.md Things you need to know before fixing anything
│   └── findings.md            Detailed entries per item
├── archive/                   Historical record. Frozen — do not edit.
│   ├── README.md              What's here and why
│   ├── specs/                 Original design spec (2026-04-10)
│   └── plans/                 Implementation plan (2026-04-10)
├── main.typ / main.pdf        Slide deck (Typst source + render)
└── whitepaper.typ / whitepaper.pdf  Whitepaper (Typst source + render)
```

## Where to start

| If you want to... | Read |
|---|---|
| Understand what this repo is | `architecture/system-overview.md` |
| See where the project stands today | `project/STATUS.md` |
| See what's planned | `project/ROADMAP.md` |
| See what we're working on this iteration | `project/FOCUS.md` |
| Pick something to work on | `improvements/README.md` → `improvements/findings.md` |
| Cut a release | `project/RELEASING.md` + `project/VERSIONING.md` |
| Add a new voting module | `framework/privacy-dimensions.md` + an existing `architecture/module-*.md` as a template |
| Touch the client (Flutter) | `standards/client-conventions.md` + `standards/visual-design-guide.md` |
| See how the system was originally designed | `archive/specs/` (frozen, may be stale) |

## Conventions

- **Living docs** (`architecture/`, `framework/`, `standards/`, `improvements/`) describe the system **as it is today** and stay current with the code. If they drift, file a P0 in `improvements/findings.md`.
- **Archive** (`archive/`) describes the system **as it was once planned**. Treat as read-only history. Don't update it to match current code — file a new doc instead.
- **Whitepaper / slides** at the root are publication artifacts. They lag the code intentionally and only update on releases.

## Editing rules

- One PR, one doc change. Don't bundle docs with code unless the doc directly describes the code being changed.
- Docs use kebab-case filenames.
- Architecture docs follow the section order of `module-m1-anon-voting.md` (Privacy Dimensions / How It Works / State Machine / Initialization / Key Functions / Security Properties / Known Limitations). Match it for consistency.
