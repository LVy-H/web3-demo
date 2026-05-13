import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright config — doubles as the demo-video capture rig.
 *
 * Videos for ALL tests land at:
 *   codes/frontend/test-results/<test-name>/video.webm
 *
 * HTML report (opens manually) at:
 *   codes/frontend/playwright-report/index.html
 *
 * The dev server is auto-started via `webServer`. In CI, `reuseExistingServer`
 * is false so each run gets a fresh server; locally it's reused for speed.
 */
export default defineConfig({
    testDir: './e2e',
    outputDir: './test-results',

    // Demo-video friendly: deterministic, no parallel races in the recording.
    fullyParallel: false,
    workers: 1,
    forbidOnly: !!process.env.CI,
    retries: process.env.CI ? 1 : 0,
    timeout: 60_000,
    expect: { timeout: 10_000 },

    reporter: [
        ['list'],
        ['html', { open: 'never', outputFolder: 'playwright-report' }],
    ],

    use: {
        baseURL: 'http://localhost:5173',
        // Video for EVERY test — demo capture is a first-class deliverable.
        video: 'on',
        trace: 'on',
        screenshot: 'only-on-failure',
        // 1280x720 = clean 16:9 ratio for recorded videos.
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
                // slowMo gives recorded videos readable pacing without
                // needing real waitForTimeout calls inside tests.
                launchOptions: { slowMo: process.env.CI ? 0 : 150 },
            },
        },
    ],

    webServer: {
        command: 'npm run dev',
        url: 'http://localhost:5173',
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
        stdout: 'ignore',
        stderr: 'pipe',
    },
})
