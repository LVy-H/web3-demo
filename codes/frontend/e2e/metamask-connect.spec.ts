/**
 * Real-MetaMask connect flow — drives the actual extension via Synpress.
 *
 * Distinct from the mock-connector tests in 01-connect-and-identity: this proves
 * the injected() connector + viem provider chain work against a real wallet,
 * which is what the user hits in production.
 *
 * Preconditions:
 *   1. `npx synpress` has been run to build the wallet cache (one-time).
 *   2. The dApp is reachable at http://localhost:5173.
 *   3. A Hardhat node is reachable at http://localhost:8545 with deployed contracts.
 *
 * Run via:
 *   nix shell nixpkgs#chromium -c \
 *     npx playwright test --config=playwright-metamask.config.ts
 */
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { testWithSynpress } from '@synthetixio/synpress'
import { metaMaskFixtures, MetaMask } from '@synthetixio/synpress/playwright'
import hardhatSetup, { HARDHAT_PASSWORD } from './wallet-setup/hardhat.setup'

const SYNPRESS_CACHE_PRESENT = existsSync(join(process.cwd(), '.cache-synpress'))

const test = testWithSynpress(metaMaskFixtures(hardhatSetup))
const { expect } = test

test.describe('Real MetaMask connect', () => {
    // Auto-skip when the Synpress cache hasn't been built — keeps the spec
    // from polluting the green E2E run. To enable this test:
    //   npm run test:e2e:metamask:cache    # one-time, headed
    //   npm run test:e2e:metamask          # then run via the metamask config
    test.skip(
        !SYNPRESS_CACHE_PRESENT,
        'Synpress wallet cache not built — run `npm run test:e2e:metamask:cache` first',
    )

    test('Connect Wallet → MetaMask popup → header shows truncated address', async ({
        context,
        page,
        metamaskPage,
        extensionId,
    }) => {
        const metamask = new MetaMask(context, metamaskPage, HARDHAT_PASSWORD, extensionId)

        // The page fixture already navigated to '/' on setup; clicking
        // Connect Wallet kicks off the dApp's addHardhatNetwork() (which
        // pops wallet_addEthereumChain) followed by connectAsync (which
        // pops eth_requestAccounts).
        await page.getByRole('button', { name: /Connect Wallet/i }).click()

        // Popup #1: approve the network add. Skip silently if MM already
        // had Hardhat (we don't pre-add in setup, but a previous test run
        // may have left state).
        await metamask.approveNewNetwork().catch(() => {})

        // Popup #2: approve the dApp connection (eth_requestAccounts).
        await metamask.connectToDapp()

        // Header swaps to the connected branch — same assertion as the mock test.
        await expect(page.getByText(/0xf39F\.\.\.2266/i)).toBeVisible({ timeout: 15_000 })
    })
})
