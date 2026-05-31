import { test, expect } from '@playwright/test'

/**
 * Real-browser coverage for the dApp paths that don't require a wallet
 * extension — the bug surfaces the user actually hits.
 *
 * What this guards against (each test name maps to the bug or behaviour):
 *
 *   1. Connect Wallet click without window.ethereum used to be a silent no-op
 *      (bug reported during dev/lvh). Fixed in App.tsx by checking for the
 *      provider and surfacing a rose banner. This spec asserts the banner
 *      and the Install MetaMask link.
 *
 *   2. Dismiss button used to fail to close the banner because wagmi's
 *      mutation-level error was sticky and only the local state was cleared.
 *      Fixed by also calling reset() from useConnect()/useSwitchChain().
 *      This spec asserts Dismiss actually closes it.
 *
 *   3. CreatePoll is the form-builder feature ("Google-Forms-style poll
 *      authoring"). Tests cover live preview updates, type radio swaps,
 *      dynamic option rows, and the Deploy button's connection gate.
 *
 * No MetaMask required — we explicitly assert the no-provider error path
 * (which IS the production state for a user without an extension installed).
 */

test.describe('Connect Wallet without provider', () => {
    test('rose banner appears with Install MetaMask link', async ({ page }) => {
        // Defensive: this Chromium has no wagmi-injected provider, so
        // window.ethereum is undefined. That's exactly the path we test.
        await page.goto('/')
        await page.getByRole('button', { name: /Connect Wallet/i }).click()

        // Banner appears.
        const banner = page.getByText(/No wallet detected/i)
        await expect(banner).toBeVisible({ timeout: 5_000 })

        // Banner has the Install MetaMask outbound link.
        const installLink = page.getByRole('link', { name: /Install MetaMask/i })
        await expect(installLink).toBeVisible()
        await expect(installLink).toHaveAttribute('href', /metamask\.io/)
        await expect(installLink).toHaveAttribute('target', '_blank')
    })

    test('Dismiss closes the banner', async ({ page }) => {
        await page.goto('/')
        await page.getByRole('button', { name: /Connect Wallet/i }).click()

        const dismiss = page.getByRole('button', { name: /Dismiss/i })
        await expect(dismiss).toBeVisible({ timeout: 5_000 })

        await dismiss.click()

        // Banner is gone — both local state AND wagmi useConnect.error must clear.
        // (Bug regression check: was failing because Dismiss only cleared local state.)
        await expect(dismiss).toBeHidden({ timeout: 3_000 })
        await expect(page.getByText(/No wallet detected/i)).toBeHidden()
    })

    test('clicking Connect Wallet again after Dismiss re-opens the banner', async ({ page }) => {
        await page.goto('/')
        await page.getByRole('button', { name: /Connect Wallet/i }).click()
        await page.getByRole('button', { name: /Dismiss/i }).click()
        await expect(page.getByRole('button', { name: /Dismiss/i })).toBeHidden({ timeout: 3_000 })

        // Re-click — banner must reappear (proves error tracking still works
        // after Dismiss; not muted forever).
        await page.getByRole('button', { name: /Connect Wallet/i }).click()
        await expect(page.getByRole('button', { name: /Dismiss/i })).toBeVisible({ timeout: 5_000 })
    })
})

test.describe('CreatePoll form-builder', () => {
    test('live preview updates as title is typed', async ({ page }) => {
        await page.goto('/create')

        const title = page.getByLabel(/01 · TITLE/i).or(page.locator('#poll-title'))
        await title.fill('Q3 Treasury Allocation')

        // PreviewPanel mirrors what voters will see.
        const preview = page.getByText('Q3 Treasury Allocation', { exact: false })
        await expect(preview).toBeVisible()
    })

    test('type radio swaps preview chip from ZK to Commit-Reveal', async ({ page }) => {
        await page.goto('/create')

        // Preview chip uses ALL-CAPS exact text (rendered uppercase via CSS but
        // the source string is uppercase, distinct from the radio's "Anonymous · ZK").
        // Using exact case + .first() to disambiguate from the radio label.
        const previewChip = page.getByText('ANONYMOUS · ZK', { exact: true })
        await expect(previewChip).toBeVisible()

        // Click blind radio → chip swaps to BLIND · COMMIT-REVEAL.
        await page.getByRole('radio', { name: /Blind · Commit-Reveal/i }).click()
        await expect(page.getByText('BLIND · COMMIT-REVEAL', { exact: true })).toBeVisible()

        // Reveal-window field appears (only on blind).
        await expect(page.getByLabel(/REVEAL WINDOW/i)).toBeVisible()
    })

    test('add option row + remove option row', async ({ page }) => {
        await page.goto('/create')

        // Two option rows by default. Add one → three rows.
        await page.getByRole('button', { name: /ADD OPTION/i }).click()
        const optionInputs = page.locator('input[id^="option-"]')
        await expect(optionInputs).toHaveCount(3)

        // Remove buttons appear only when count > 2.
        const removeButtons = page.getByRole('button', { name: /Remove option/i })
        await expect(removeButtons.first()).toBeVisible()
        await removeButtons.first().click()
        await expect(optionInputs).toHaveCount(2)
    })

    test('Deploy button is disabled until wallet connects', async ({ page }) => {
        await page.goto('/create')

        // Without a connected wallet, the deploy button shows the connect-wallet copy.
        const deploy = page.getByRole('button', { name: /CONNECT WALLET TO DEPLOY/i })
        await expect(deploy).toBeVisible()
        await expect(deploy).toBeDisabled()

        // The "Wallet not connected" sidebar advisory is also visible.
        await expect(page.getByText(/Wallet not connected/i)).toBeVisible()
    })
})
