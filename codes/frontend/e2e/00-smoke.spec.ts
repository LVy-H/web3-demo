import { test, expect } from '@playwright/test'

/**
 * Smoke test — fastest sanity check.
 *
 * Verifies the app boots, the document title is set, and the hero heading
 * is visible. No wallet, no contract — pure UI render.
 */
test.describe('Smoke', () => {
    test('home page renders title and hero heading', async ({ page }) => {
        await page.goto('/')

        // Document title set in index.html.
        await expect(page).toHaveTitle('Voting Hub')

        // Hero heading rendered by pages/Home.tsx (Dark Bauhaus renames it
        // from the old "Anonymous Voting" hero to the giant "POLLS" wordmark).
        const hero = page.getByRole('heading', { level: 1, name: /POLLS/i })
        await hero.waitFor({ state: 'visible' })
        await expect(hero).toBeVisible()

        // Navigation chrome is present.
        await expect(page.getByRole('link', { name: /Dashboard/i }).first()).toBeVisible()
        await expect(page.getByRole('link', { name: /Create Poll/i }).first()).toBeVisible()
    })
})
