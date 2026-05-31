import { test, expect } from '@playwright/test'

/**
 * Live Meeting Vote — route + render smokes (S1.7, no-wallet tier).
 *
 * These run against just the dev server (no chain, no wallet, no relayer) and
 * verify the new /live routes MOUNT and render their no-auth states without a
 * runtime crash:
 *   - the host page shows the owner gate when no wallet is connected;
 *   - the voter page shows the "get a fresh code" notice for a bad/absent ticket.
 *
 * The full happy/reject flow (real registerVoter + relayed vote) needs the whole
 * local stack and lives in 09-live-two-context.spec.ts.
 */

const POLL = '0x5FbDB2315678afecb367f032d93F642f64180aa3'

test.describe('Live Meeting — route smokes', () => {
  test('host page mounts and shows the organizer-wallet gate (no wallet)', async ({ page }) => {
    await page.goto(`/live/${POLL}/host`)
    await expect(page.getByRole('heading', { name: /LIVE MEETING/i })).toBeVisible()
    await expect(page.getByTestId('phase-label')).toBeVisible()
    // Not the owner (no wallet) → host controls hidden behind the gate.
    await expect(page.getByText(/connect the organizer wallet that/i)).toBeVisible()
  })

  test('voter page shows the fresh-code notice for a malformed ticket', async ({ page }) => {
    await page.goto(`/live/${POLL}/vote?t=this-is-not-a-valid-ticket`)
    await expect(page.getByRole('heading', { name: /Code expired/i })).toBeVisible()
    await expect(page.getByText(/Scan the projected QR again/i)).toBeVisible()
  })

  test('voter page shows the fresh-code notice when the ticket is missing', async ({ page }) => {
    await page.goto(`/live/${POLL}/vote`)
    await expect(page.getByRole('heading', { name: /Code expired/i })).toBeVisible()
  })
})
