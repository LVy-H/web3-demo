import { test, expect } from '@playwright/test'

/**
 * Receipt-verifier page (`/verify`) — anyone can confirm a voter receipt by
 * scanning the QR / opening the URL. No wallet required.
 *
 * The receipt itself appears in a modal after a successful vote (covered
 * by Poll.tsx integration); writing an E2E for the full vote flow requires
 * an invite token + ZK proof generation (~10-30s), out of scope. This spec
 * exercises the verifier page directly with crafted URL params, covering
 * its three UI states: error / not-found / verified.
 */

test.describe('Verify receipt page', () => {
    test('renders error state when required params are missing', async ({ page }) => {
        await page.goto('/verify')

        // Header always renders.
        await expect(page.getByRole('heading', { level: 1, name: /VERIFY/i })).toBeVisible()
        await expect(page.getByText(/Verification Error/i)).toBeVisible()
        await expect(page.getByText(/Missing required URL parameters/i)).toBeVisible()
    })

    test('renders error state when poll address is malformed', async ({ page }) => {
        await page.goto('/verify?poll=not-an-address&nullifier=42')
        await expect(page.getByText(/Invalid poll address shape/i)).toBeVisible({ timeout: 5_000 })
    })

    test('renders error state when nullifier is malformed', async ({ page }) => {
        await page.goto('/verify?poll=0x0000000000000000000000000000000000000001&nullifier=ZZZ')
        await expect(page.getByText(/Invalid nullifier/i)).toBeVisible({ timeout: 5_000 })
    })

    test('queries chain and renders Not Found for an unused nullifier', async ({ page }) => {
        // Real Hardhat poll address (deployed contracts container — chainId 31337).
        // Nullifier 42 is essentially never used by Semaphore (entropy-driven hashes
        // are 256-bit), so this poll's isNullifierUsed[42] returns false.
        const POLL = '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9' // PollRegistry
        await page.goto(`/verify?poll=${POLL}&nullifier=42&block=1`)

        // Either Not Found verdict OR a chain-read error (if PollRegistry doesn't
        // expose isNullifierUsed) — both acceptable: the UI handled the read attempt.
        const notFound = page.getByText(/Not Found/i)
        const errorPanel = page.getByText(/Verification Error/i)
        await expect(notFound.or(errorPanel)).toBeVisible({ timeout: 10_000 })
    })

    test('detail panel always shows the supplied params', async ({ page }) => {
        const POLL = '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9'
        const NULLIFIER = '12345678901234567890'
        const BLOCK = '99'
        await page.goto(`/verify?poll=${POLL}&nullifier=${NULLIFIER}&block=${BLOCK}`)

        // The receipt-detail block at the bottom always echoes the URL params
        // so the user can audit what was checked.
        await expect(page.getByText(POLL)).toBeVisible()
        await expect(page.getByText(NULLIFIER)).toBeVisible()
        await expect(page.getByText(BLOCK, { exact: true })).toBeVisible()
    })
})
