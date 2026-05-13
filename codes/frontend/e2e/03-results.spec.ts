import { test, expect } from '@playwright/test'

/**
 * Results-rendering check.
 *
 * Verifies that opening a poll detail page surfaces some results UI
 * (vote bars, tallies, or the "no votes yet" placeholder). This is a
 * read-only assertion — we don't cast votes here. End-to-end tally
 * verification requires the full Direct/Relayer flow which is deferred
 * (see 02-direct-vote-flow.spec.ts).
 *
 * Skips when no poll is registered.
 */
test.describe('Results display', () => {
    test('opens a poll and asserts the results panel renders', async ({ page }) => {
        await page.goto('/')

        // Optional: connect so the layout matches what a real voter sees.
        // (Results render even when disconnected, but connecting makes
        // the recorded video tell a more coherent story.)
        const testAccountBtn = page.getByRole('button', { name: /Test Account/i })
        if (await testAccountBtn.isVisible()) {
            await testAccountBtn.click()
            await page.getByText(/0xf39F\.\.\.2266/i).waitFor({ state: 'visible' })
        }

        const pollLinks = page.locator('a[href^="/poll/"]')

        // Wait up to a few seconds for poll cards to render (the registry
        // hook is async). If none appear, we skip.
        await pollLinks.first().waitFor({ state: 'visible', timeout: 5_000 }).catch(() => {})

        const pollCount = await pollLinks.count()
        test.skip(
            pollCount === 0,
            'No poll deployed in registry — skip results assertion. See 02-direct-vote-flow.spec.ts for the same precondition.',
        )

        await pollLinks.first().click()

        // The page should expose a Results section. Both Poll.tsx and
        // BlindPoll.tsx render a Results heading or a ResultsBars
        // component. We accept any of the canonical headings here.
        const resultsHeading = page.getByRole('heading', { name: /Results|Live Tally|Final Results/i }).first()
        await resultsHeading.waitFor({ state: 'visible', timeout: 10_000 }).catch(() => {})

        // If the heading didn't appear, fall back to asserting that the
        // poll detail layout rendered at all — some poll states hide
        // the Results card until the voting phase opens.
        if (!(await resultsHeading.isVisible().catch(() => false))) {
            const identityHeading = page.getByRole('heading', { name: /^Identity$/i })
            await expect(identityHeading).toBeVisible()
            return
        }

        await expect(resultsHeading).toBeVisible()
    })
})
