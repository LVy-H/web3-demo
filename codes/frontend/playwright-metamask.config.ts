import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright config for the Synpress-driven real-MetaMask suite.
 *
 * NixOS notes:
 *   - Branded `google-chrome-stable` (Chrome 137+) removed --load-extension,
 *     so we cannot use it for extension tests. Unbranded `chromium` (from
 *     nixpkgs) still supports it.
 *   - Run via `nix shell nixpkgs#chromium -c npx playwright test ...` so the
 *     unbranded chromium is in PATH; Synpress will pick it up.
 *   - Synpress mandates headed mode (extensions don't work headless) — this
 *     means a real browser window pops up on DISPLAY. On CI, wrap the npx
 *     invocation in `xvfb-run`.
 *
 * This config does NOT define a `webServer` block. Bring up the docker stack
 * (or the dev server) manually before running.
 */
export default defineConfig({
    testDir: './e2e',
    testMatch: /metamask-.*\.spec\.ts$/,
    outputDir: './test-results-metamask',
    fullyParallel: false,
    workers: 1,
    timeout: 120_000, // wallet popups + network switch can be slow first time
    expect: { timeout: 10_000 },
    reporter: [['list'], ['html', { open: 'never', outputFolder: 'playwright-report-metamask' }]],
    use: {
        baseURL: 'http://localhost:5173',
        video: 'on',
        trace: 'on',
        screenshot: 'only-on-failure',
        viewport: { width: 1280, height: 720 },
        actionTimeout: 10_000,
        navigationTimeout: 30_000,
        // MetaMask extension can't run headless — Synpress docs are explicit
        // about this. headed = visible browser window on DISPLAY=:0.
        headless: false,
        launchOptions: {
            // Avoid the NixOS libglib problem on Playwright's bundled chromium-1223
            // by pointing at the Nix-managed chromium (also unbranded, also
            // supports --load-extension which branded Chrome 137+ removed).
            // Stable Nix-store path resolved from `nix shell nixpkgs#chromium`.
            // Use the same bridged path the cache build used so the wallet
            // state restores cleanly. (~/.cache/ms-playwright/chromium-1140/
            // chrome-linux/chrome → symlink to the Nix chromium binary.)
            executablePath:
                process.env.CHROMIUM_BIN ??
                `${process.env.HOME}/.cache/ms-playwright/chromium-1140/chrome-linux/chrome`,
        },
    },
    projects: [
        {
            name: 'chromium-with-metamask',
            use: { ...devices['Desktop Chrome'] },
        },
    ],
})
