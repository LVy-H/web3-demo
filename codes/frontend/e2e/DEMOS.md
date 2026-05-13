# Playwright Demo Videos

Playwright is configured (see `../playwright.config.ts`) with `video: 'on'` so
**every** test run produces a `.webm` recording at
`codes/frontend/test-results/<test-slug>/video.webm`. These are the project's
demo videos — first-class deliverables, not debug artifacts.

The HTML report at `codes/frontend/playwright-report/index.html` collects each
test's status + embedded video + trace for one-click playback.

> Videos and the HTML report are **gitignored** (root `.gitignore`):
> `codes/frontend/test-results/` and `codes/frontend/playwright-report/`. Each
> developer regenerates them locally; only this file is committed.

---

## Latest captured run

Captured on the `dev/lvh` worktree (branch `imp/T-I-sepolia-deploy-prep`),
chromium project, viewport 1280x720, `slowMo: 150`, mock wallet (Hardhat #0
= `0xf39F...2266`).

| Test ID | Status | Video (relative to `codes/frontend/`) | What it shows |
|---|---|---|---|
| 00-smoke | passed | `test-results/00-smoke-Smoke-home-page-renders-title-and-hero-heading-chromium/video.webm` | App boots, title "Voting Hub" sets, hero heading "Anonymous Voting" + Dashboard / Create Poll nav links render. |
| 01-connect-and-identity (Test Account button) | passed | `test-results/01-connect-and-identity-Wa-42e6c-and-shows-truncated-address-chromium/video.webm` | Clicks dev-only "Test Account" button, asserts truncated address badge `0xf39F...2266` and "Disconnect wallet" control appear. |
| 01-connect-and-identity (Disconnect) | passed | `test-results/01-connect-and-identity-Wa-22523-er-to-the-unconnected-state-chromium/video.webm` | Same flow then clicks "Disconnect wallet" — header swaps back to the unconnected state. |
| 02-direct-vote-flow (panel renders) | skipped | `test-results/02-direct-vote-flow-Direct-ca908-ts-the-voting-panel-renders-chromium/video.webm` | Pre-skip: connects wallet, scans dashboard. Skipped via `test.skip(pollCount === 0, ...)` because no poll is registered in this clean redeploy. Video shows the empty dashboard state. |
| 03-results (panel renders) | skipped | `test-results/03-results-Results-display-e3dc3-s-the-results-panel-renders-chromium/video.webm` | Skipped — depends on a deployed poll. Video shows pre-skip steps (home page + dashboard scan). |
| 04-clear-identity-no-duplicate (regression) | skipped | `test-results/04-clear-identity-no-dupli-59d1f-regression-58248a2-e87de1b--chromium/video.webm` | Skipped — depends on at least one poll with an active invite token. Video shows pre-skip dashboard scan. |

> Tests 02-03-04 will turn green once at least one poll is created via the
> "Create Poll" UI between the contract deploy step and the Playwright run.
> Skip reasons are baked into the test bodies — re-deploy + create-one-poll
> is the unblock recipe.

`test-results/02-direct-vote-flow-Direct-16b51-end-unblock-when-T-C-lands--chromium/`
exists from a different skipped variant (`cast a Relayer-mode vote end-to-end`)
that emits no video because the skip fires before any page navigation.

---

## How to view the videos

```bash
# 1. Open one of the produced videos directly
xdg-open codes/frontend/test-results/00-smoke-Smoke-home-page-renders-title-and-hero-heading-chromium/video.webm

# 2. Or open the HTML report for the full timeline + traces
xdg-open codes/frontend/playwright-report/index.html

# 3. Or replay any trace step-by-step
codes/frontend/node_modules/.bin/playwright show-trace \
  codes/frontend/test-results/01-connect-and-identity-Wa-42e6c-and-shows-truncated-address-chromium/trace.zip
```

`.webm` plays in Firefox, Chrome, VLC, mpv. Each video is 1280x720, ~50 KB to
~200 KB depending on test duration.

---

## How to reproduce the videos

The full demo-capture run on this NixOS workstation requires four moving
parts (Hardhat node + deployed contracts + Vite dev server + Playwright).
Run from the repo root.

```bash
# --- 1. Hardhat local node -------------------------------------------------
cd codes/contracts
npm install --ignore-scripts          # if not already
# NOTE on NixOS: the .bin/hardhat shim hits "Exec format error" because the
# cached binary is for a different arch. Invoke node directly:
nohup node node_modules/hardhat/internal/cli/bootstrap.js node \
  > /tmp/hardhat.log 2>&1 &
echo "HARDHAT_PID=$!"
# Wait until JSON-RPC responds with chainId 0x7a69 (31337):
until curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://127.0.0.1:8545 | grep -q '"result"'; do sleep 1; done

# --- 2. Deploy contracts ---------------------------------------------------
# Same workaround for the hardhat shim:
node node_modules/hardhat/internal/cli/bootstrap.js \
  run scripts/deploy.ts --network localhost
# Writes deployed addresses to ../frontend/src/deployed-addresses.json

# (Optional) Create at least one poll via the UI now if you want tests
# 02 / 03 / 04 to run instead of skip.

# --- 3. Vite dev server ----------------------------------------------------
cd ../frontend
npm install --ignore-scripts          # if not already
nohup node node_modules/vite/bin/vite.js dev > /tmp/vite.log 2>&1 &
echo "VITE_PID=$!"
until curl -s -o /dev/null -w '%{http_code}' http://localhost:5173 \
  | grep -q 200; do sleep 1; done

# --- 4. Playwright browser install ----------------------------------------
# Playwright 1.60 bundles Chromium 1223. The thin `playwright install`
# entrypoint is broken on this Node 24 setup; call playwright-core's CLI
# directly:
node node_modules/playwright-core/cli.js install chromium chromium-headless-shell

# --- 5. Run the suite ------------------------------------------------------
# *** NixOS WORKAROUND ***
# The Playwright-bundled Chromium can't dlopen system glibc/libnspr on
# NixOS (missing libglib-2.0.so.0, libnspr4.so, etc.). Use a config that
# points executablePath at /etc/profiles/per-user/$USER/bin/google-chrome-stable
# (or any FHS-wrapped Chromium you have). On a standard Ubuntu/macOS host
# the stock `npm run test:e2e` works without the override.
#
# On this host, the override config is gitignored and lives at:
#   codes/frontend/playwright-syschrome.config.ts
# If it's missing, recreate it with the snippet at the bottom of this file.
node node_modules/@playwright/test/cli.js test \
  --config=playwright-syschrome.config.ts --project=chromium

# --- 6. Cleanup ------------------------------------------------------------
kill $HARDHAT_PID $VITE_PID 2>/dev/null
```

On a non-NixOS host (standard Ubuntu / macOS), skip the override config and
run the stock script — it auto-starts vite via Playwright's `webServer`:

```bash
cd codes/frontend
npx playwright install chromium
npm run test:e2e          # or: npm run test:e2e:headed
```

---

## NixOS executablePath override (re-create if deleted)

`codes/frontend/playwright-syschrome.config.ts` — **not committed**, regenerate
locally:

```ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
    testDir: './e2e',
    outputDir: './test-results',
    fullyParallel: false,
    workers: 1,
    retries: 0,
    timeout: 60_000,
    expect: { timeout: 10_000 },
    reporter: [
        ['list'],
        ['html', { open: 'never', outputFolder: 'playwright-report' }],
    ],
    use: {
        baseURL: 'http://localhost:5173',
        video: 'on',
        trace: 'on',
        screenshot: 'only-on-failure',
        viewport: { width: 1280, height: 720 },
        actionTimeout: 10_000,
        navigationTimeout: 30_000,
    },
    projects: [
        {
            name: 'chromium',
            use: {
                ...devices['Desktop Chrome'],
                viewport: { width: 1280, height: 720 },
                launchOptions: {
                    slowMo: 150,
                    executablePath:
                        '/etc/profiles/per-user/hoang/bin/google-chrome-stable',
                },
            },
        },
    ],
    // No webServer here — vite is started externally above.
})
```
