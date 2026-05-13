import { test, expect } from '@playwright/test'

/**
 * Regression test — "Clear identity must not duplicate the input section".
 *
 * User-reported bug (Vietnamese: "khúc nhập bị nhân đôi"): after clicking
 * the per-poll "Clear" identity button, the identity-input section gets
 * rendered twice. This was traced to two coupled defects fixed in T-C:
 *
 *   - 58248a2  Set-based group dedup (useGroupSync) — prevented duplicate
 *              commitment insertion that confused downstream identity UI.
 *   - e87de1b  identity-clear properly resets local state — the "Clear"
 *              handler now also clears `inviteToken` + `groupSync.reset()`
 *              + `hasVoted`, so the Identity card re-mounts cleanly into
 *              its "no identity" branch with a single input.
 *
 * Mechanism of the fix in pages/Poll.tsx:
 *
 *   - Identity card branches on `localIdentity`:
 *       null  -> renders ONE <input aria-label="Invite token"> + "Load Identity"
 *       set   -> renders the "Identity Ready" badge + "Clear" button
 *
 *   - The "Clear" button (Poll.tsx ~line 556-569) resets ALL the dependent
 *     pieces. If e87de1b regresses, leftover state could cause the input
 *     section to render twice (e.g. once from the cleared branch, once from
 *     stale state) — this test catches that.
 *
 * Strategy (no "Generate Local Identity" button exists in this codebase;
 * Poll.tsx loads identity from an invite-token string). We:
 *
 *   1. Open a poll detail page (skip if no poll deployed — see 02/03).
 *   2. Assert: identity-input count === 1 (initial state).
 *   3. Paste a valid 64-char hex token, click "Load Identity".
 *   4. Assert: count === 0 (input replaced by "Identity Ready" badge).
 *   5. Click "Clear" — the regression-proof step.
 *   6. Assert: count === 1 (NOT 2 — that would be the bug).
 *   7. Paste a SECOND token to prove no stale state poisoned the input.
 *   8. Listen to console — no /duplicate|already exists/ errors.
 *
 * `new Identity(<hex>)` accepts any 64-char hex string, so 'a'.repeat(64)
 * is a valid synthetic token — no chain interaction required.
 */
test.describe('Clear-identity does not duplicate input section [bug: nhập bị nhân đôi]', () => {
    test('input section appears exactly ONCE after Clear (regression: 58248a2 + e87de1b)', async ({ page }) => {
        // -- Console-error listener MUST attach before navigation, otherwise
        // we miss errors emitted during initial boot / wallet hydration.
        const consoleErrors: string[] = []
        page.on('console', msg => {
            if (msg.type() === 'error') consoleErrors.push(msg.text())
        })

        await page.goto('/')

        // Connect mock wallet (matches 02/03 pattern). Identity card lives
        // on the per-poll page, which renders regardless of connection,
        // but connecting makes the recorded video coherent.
        await page.getByRole('button', { name: /Test Account/i }).click()
        await page.getByText(/0xf39F\.\.\.2266/i).waitFor({ state: 'visible' })

        // -- Locate a poll card. Same skip envelope as 02 + 03: bootstrapping
        // a poll from inside an E2E test is brittle and out of scope.
        const pollLinks = page.locator('a[href^="/poll/"]')
        await pollLinks.first().waitFor({ state: 'visible', timeout: 5_000 }).catch(() => {})

        const pollCount = await pollLinks.count()
        test.skip(
            pollCount === 0,
            'No poll deployed in registry — skip clear-identity regression test. Run `npm run deploy:local` + create a poll first.',
        )

        await pollLinks.first().click()

        // -- The Identity heading appears on both Poll.tsx and BlindPoll.tsx.
        // Wait for it before counting locators (avoids a race against the
        // PollRouter loading skeleton).
        const identityHeading = page.getByRole('heading', { name: /^Identity$/i })
        await identityHeading.waitFor({ state: 'visible' })

        // BlindPoll uses a different identity flow — only Poll.tsx (anon-vote)
        // has the "Invite token" input. If we landed on a blind poll, skip
        // rather than false-fail.
        const inviteInput = page.getByLabel('Invite token')
        const initialInputCount = await inviteInput.count()
        test.skip(
            initialInputCount === 0,
            'First poll in registry is not an anon-vote poll (no "Invite token" input) — regression test is anon-vote specific.',
        )

        // ===== STEP 1: Initial state — exactly ONE input section =====
        await expect(
            inviteInput,
            'On fresh poll detail page with no identity loaded, the "Invite token" input must render exactly once.',
        ).toHaveCount(1)

        // ===== STEP 2: Load an identity via a synthetic invite token =====
        // `new Identity(hex)` accepts any 64-char hex — no on-chain step needed
        // because we are NOT casting a vote, only exercising the load/clear UI.
        const SYNTHETIC_TOKEN = 'a'.repeat(64)
        await inviteInput.fill(SYNTHETIC_TOKEN)
        await page.getByRole('button', { name: /Load Identity/ }).click()

        // After load, the card swaps to the "Identity Ready" badge branch —
        // the input must DISAPPEAR. (count === 0 here is part of the fix:
        // if pre-fix state leaked, the input could still be present.)
        await expect(
            page.getByText(/Identity Ready/i),
            'After Load Identity, the "Identity Ready" badge should appear.',
        ).toBeVisible()
        await expect(
            inviteInput,
            'After Load Identity, the "Invite token" input should be hidden (replaced by Identity Ready badge).',
        ).toHaveCount(0)

        // ===== STEP 3: Click "Clear" — THIS is the regression-proof step =====
        // Dark Bauhaus IdentityCard renders the button text as `[ Clear ↵ ]`
        // (decorative brackets + return-arrow glyph). The accessible name is
        // that whole string, so we match the literal "Clear" substring.
        // No other "Clear" button exists on the poll page — verified by grep
        // across pages/ + components/.
        const clearButton = page.getByRole('button', { name: /Clear/ })
        await clearButton.click()

        // ===== STEP 4: REGRESSION ASSERTION — count MUST be 1, not 2 =====
        // Before the e87de1b fix, leftover state caused the Identity card to
        // remount in a way that rendered the input twice. The fix resets
        // inviteToken + hasVoted + groupSync so the no-identity branch
        // renders cleanly once.
        await expect(
            inviteInput,
            'REGRESSION: after Clear, the "Invite token" input must appear EXACTLY ONCE. ' +
                'A count of 2 means the bug "khúc nhập bị nhân đôi" (input duplicated) has returned. ' +
                'Check commits 58248a2 (Set-based group dedup) and e87de1b (identity-clear reset).',
        ).toHaveCount(1)

        // The "Load Identity" button should also appear exactly once — it
        // is rendered inside the same branch as the input.
        await expect(
            page.getByRole('button', { name: /Load Identity/ }),
            'After Clear, the "Load Identity" button must appear exactly once.',
        ).toHaveCount(1)

        // The status banner should report the clear (small bonus: confirms
        // the click reached the handler).
        await expect(page.getByText(/Identity cleared\./i)).toBeVisible()

        // ===== STEP 5: Load a SECOND identity — prove no stale state =====
        // If group/state weren't reset, loading a fresh token after Clear
        // might log a /duplicate|already/ console error from useGroupSync.
        await inviteInput.fill('b'.repeat(64))
        await page.getByRole('button', { name: /Load Identity/ }).click()

        await expect(
            page.getByText(/Identity Ready/i),
            'After loading a SECOND identity post-Clear, the Ready badge should appear cleanly.',
        ).toBeVisible()
        await expect(
            inviteInput,
            'After second Load Identity, the input must disappear again.',
        ).toHaveCount(0)

        // ===== STEP 6: Assert no regression-shaped console errors =====
        // We don't require zero errors (RPC / wallet hydration may legit
        // emit some), only that NONE of them carry the bug fingerprint.
        const regressionErrors = consoleErrors.filter(e =>
            /duplicate input|already exists|already registered/i.test(e),
        )
        expect(
            regressionErrors,
            `Found regression-shaped console errors after clear+reload identity cycle: ${JSON.stringify(regressionErrors)}`,
        ).toEqual([])
    })
})
