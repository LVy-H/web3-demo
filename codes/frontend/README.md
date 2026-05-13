# Voting Hub — Frontend

React + Vite + wagmi/viem UI for the anonymous voting contracts.

## Quick start

```bash
cd codes/frontend
npm install
npm run dev          # http://localhost:5173
```

The dev server reads contract addresses from `src/deployed-addresses.json`
and connects to the Hardhat node at `http://127.0.0.1:8545` (override via
`VITE_RPC_URL`).

A built-in **Test Account** button appears in the header in dev mode. It
connects a wagmi `mock` connector using Hardhat account #0
(`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`). This makes the UI usable
without installing MetaMask and is what the E2E suite drives.

## E2E Tests + Demo Videos

The Playwright suite under `e2e/` doubles as a demo-video capture rig.
Videos are recorded for every test (`use.video: 'on'` in
`playwright.config.ts`) at 1280x720 with `slowMo: 150` for readable
pacing.

> **Note on `package.json` scripts.** The convenience scripts below
> (`test:e2e`, `test:e2e:install`, ...) are documented here as the
> intended UX. They are not added to `package.json` from this branch
> because `package.json` is currently mid-merge on `main`. Add them in
> the merge-resolution commit, or invoke Playwright directly:
> `npx playwright test` / `npx playwright install chromium`.

### One-time setup

```bash
cd codes/frontend
npm install                       # if you haven't already
npx playwright install chromium   # downloads the browser
# When the package.json scripts are merged in, this becomes:
#   npm run test:e2e:install
```

### Run

The Playwright config auto-starts the Vite dev server, so a clean run is:

```bash
# Optional but recommended — gives the deeper flow tests something to do
cd codes/contracts && npm run node &        # terminal 1
cd codes/contracts && npm run deploy:local  # terminal 2

# Run tests (terminal 3)
cd codes/frontend && npx playwright test
```

| Command (current) | Future script | Purpose |
| --- | --- | --- |
| `npx playwright test` | `npm run test:e2e` | Headless. Produces videos + HTML report. |
| `npx playwright test --headed` | `npm run test:e2e:headed` | Watch the browser drive itself. |
| `npx playwright test --headed --reporter=html` | `npm run test:e2e:record` | Headed + auto-opens HTML report after. |

### Outputs

- **Videos**: `codes/frontend/test-results/<test-name>/video.webm`
  (one per test — these are the demo clips).
- **HTML report**: `codes/frontend/playwright-report/index.html`
  (open in a browser to scrub through video + trace per test).
- **Failure artifacts**: screenshots + traces land alongside the video.

To share a demo:

```bash
zip -r voting-hub-demo.zip codes/frontend/test-results
# OR open the HTML report and screen-record a walk-through:
npx playwright show-report codes/frontend/playwright-report
```

Both `test-results/` and `playwright-report/` are gitignored — these are
generated artifacts.

### Test scope

| File | Coverage |
| --- | --- |
| `00-smoke.spec.ts` | Page renders, title set, navigation visible. |
| `01-connect-and-identity.spec.ts` | Mock-wallet connect/disconnect via the Test Account button. |
| `02-direct-vote-flow.spec.ts` | Connect → navigate to a poll → assert voter panel. Skips if no poll deployed. |
| `03-results.spec.ts` | Open a poll → assert the results panel renders. Skips if no poll deployed. |

The deeper "cast a vote end-to-end" assertion in `02-direct-vote-flow.spec.ts`
is `test.skip(...)` until the relayer (T-B) and the Direct/Relayer toggle
(T-C) land, since both are needed for a scriptable, deterministic vote
flow. Until then, the manual flow documented in the root `README.md`
covers that path.

### Validation gates (this branch)

Validation gates were run against the main-repo working copy at commit
`e972c33` (because the worktree this branch was authored in does not
contain `node_modules`):

- `node node_modules/typescript/bin/tsc --noEmit -p tsconfig.app.json`
  → exit 0 (e2e/ is excluded from the app tsconfig include path).
- `node node_modules/@playwright/test/cli.js test --list`
  → exit 0, 7 tests listed across 4 spec files.

To re-run after merging this branch into a tree with `package.json` +
`node_modules`:

```bash
cd codes/frontend
npm install
npx playwright test --list
```

### Tips

- `playwright test --list` validates that all spec files parse without
  starting the dev server. Useful as a fast pre-commit check.
- `PWDEBUG=1 npx playwright test --headed` opens the Playwright inspector
  for step-by-step debugging.
- To keep videos crisp, the suite runs `workers: 1` and
  `fullyParallel: false`. Do not raise these — the recordings are the
  primary deliverable.
