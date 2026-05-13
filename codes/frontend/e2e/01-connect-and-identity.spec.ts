import { test, expect } from '@playwright/test'

/**
 * Connect-wallet journey.
 *
 * Uses the dev-only "Test Account" button (gated on `import.meta.env.DEV`
 * in App.tsx and wired via wagmi's `mock` connector at src/config.ts) so
 * the test is deterministic and needs no MetaMask extension.
 *
 * Expected mock account (from src/config.ts):
 *   0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266  (Hardhat #0)
 *
 * Note on Semaphore identity: the app exposes identity creation per-poll
 * (loaded from an invite token on the Poll detail page), not as a global
 * action on the home dashboard. So we don't assert an "identity badge"
 * here — that step lives in the poll-detail flow tests (02/03).
 */
test.describe('Wallet connect', () => {
    test('Test Account button connects mock wallet and shows truncated address', async ({ page }) => {
        await page.goto('/')

        const testAccountBtn = page.getByRole('button', { name: /Test Account/i })
        await testAccountBtn.waitFor({ state: 'visible' })
        await expect(testAccountBtn).toBeVisible()

        await testAccountBtn.click()

        // After connect, App.tsx renders the truncated-address badge:
        //   `${address?.slice(0, 6)}...${address?.slice(-4)}`
        // For 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 that becomes
        // "0xf39F...2266".
        const addressBadge = page.getByText(/0xf39F\.\.\.2266/i)
        await addressBadge.waitFor({ state: 'visible' })
        await expect(addressBadge).toBeVisible()

        // Disconnect control should now be present (aria-label set in App.tsx).
        await expect(page.getByRole('button', { name: /Disconnect wallet/i })).toBeVisible()

        // Test Account button should no longer be visible (header swapped state).
        await expect(testAccountBtn).toHaveCount(0)
    })

    test('Disconnect returns the header to the unconnected state', async ({ page }) => {
        await page.goto('/')

        await page.getByRole('button', { name: /Test Account/i }).click()
        await page.getByText(/0xf39F\.\.\.2266/i).waitFor({ state: 'visible' })

        await page.getByRole('button', { name: /Disconnect wallet/i }).click()

        // Test Account button reappears once disconnected.
        await expect(page.getByRole('button', { name: /Test Account/i })).toBeVisible()
        await expect(page.getByRole('button', { name: /Connect Wallet/i })).toBeVisible()
    })
})
