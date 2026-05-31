/**
 * Synpress wallet setup — runs ONCE via `npx synpress` to bake a MetaMask
 * extension snapshot. Re-run with `--force` after every edit.
 *
 * Hash bust marker (any change triggers a fresh cache directory): v2-2026-05-14
 */
import { defineWalletSetup } from '@synthetixio/synpress'
import { MetaMask } from '@synthetixio/synpress/playwright'

export const HARDHAT_SEED =
    'test test test test test test test test test test test junk'
export const HARDHAT_PASSWORD = 'Tester@1234'

export default defineWalletSetup(HARDHAT_PASSWORD, async (context, walletPage) => {
    const metamask = new MetaMask(context, walletPage, HARDHAT_PASSWORD)
    await metamask.importWallet(HARDHAT_SEED)

    // MM 13.x post-import "Your wallet is ready!" intermediate screen — push past
    // it AND wait for the actual wallet UI to settle, so the cache snapshot
    // captures the logged-in state, not an in-flight navigation.
    const doneButton = walletPage.locator('[data-testid="onboarding-complete-done"]')
    if (await doneButton.count()) {
        await doneButton.click().catch(() => {})
        await walletPage.waitForFunction(
            () =>
                Boolean(
                    document.querySelector('[data-testid="network-display"]') ||
                        document.querySelector('[data-testid="account-menu-icon"]') ||
                        document.querySelector('.home__main-view') ||
                        document.querySelector('.app-header__logo-container'),
                ),
            { timeout: 15000 },
        ).catch(() => {})
    }

    // Dismiss any one-time modals that intercept clicks (what's-new, pin, etc.)
    for (const buttonName of ['Got it', 'Next', 'No thanks', 'Close', 'Done', 'Skip']) {
        const btn = walletPage.getByRole('button', { name: new RegExp(buttonName, 'i') }).first()
        if (await btn.count()) {
            await btn.click({ timeout: 2000 }).catch(() => {})
            await walletPage.waitForTimeout(300)
        }
    }

    // Final settle so the snapshot captures a stable state.
    await walletPage.waitForTimeout(2000)
})
