import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
    testDir: './e2e',
    // Synpress (real-MetaMask) specs run via playwright-metamask.config.ts, not here.
    testIgnore: /metamask-.*\.spec\.ts$/,
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
    // No webServer here — vite is started externally.
})
