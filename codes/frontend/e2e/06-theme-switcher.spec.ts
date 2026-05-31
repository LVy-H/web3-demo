import { test, expect } from '@playwright/test'

/**
 * Theme switcher: cycle Bauhaus → Brutalist → Cyberpunk → Bauhaus.
 * Each click rotates the theme; choice persists in localStorage.
 */

const THEMES = [
    { name: 'bauhaus', label: 'Dark Bauhaus', voidVar: '#0a0c10' },
    { name: 'brutalist', label: 'Brutalist', voidVar: '#f7f4ed' },
    { name: 'cyberpunk', label: 'Cyberpunk', voidVar: '#0a0e0a' },
]

test.describe('Theme switcher', () => {
    test('cycle through 3 themes and persist via localStorage', async ({ page }) => {
        await page.goto('/')

        // Default state: bauhaus class on <html>.
        await expect(page.locator('html')).toHaveClass(/theme-bauhaus/)

        // Cycle through each theme by clicking the toggle button.
        for (let i = 1; i < THEMES.length; i++) {
            // Click the cycle button (aria-label contains "Cycle theme").
            await page.getByRole('button', { name: /Cycle theme/i }).click()
            const expected = THEMES[i]!
            await expect(page.locator('html')).toHaveClass(new RegExp(`theme-${expected.name}`))

            // Tooltip text reflects current theme.
            await expect(page.getByRole('button', { name: /Cycle theme/i })).toHaveAttribute(
                'title',
                new RegExp(expected.label),
            )

            // Computed CSS var reflects the theme's bg.
            const voidVar = await page.evaluate(() =>
                getComputedStyle(document.documentElement)
                    .getPropertyValue('--color-db-void')
                    .trim(),
            )
            expect(voidVar).toBe(expected.voidVar)
        }

        // localStorage persists the active theme.
        const stored = await page.evaluate(() => localStorage.getItem('theme'))
        expect(stored).toBe('cyberpunk')

        // Reload picks up the stored theme.
        await page.reload()
        await expect(page.locator('html')).toHaveClass(/theme-cyberpunk/)
    })
})
