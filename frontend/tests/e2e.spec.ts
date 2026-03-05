import { test, expect } from '@playwright/test';

test('ZK Voting and Lottery E2E flow', async ({ page }) => {
    // 1. Visit the app
    await page.goto('/');

    // wait a bit for react rendering
    await page.waitForTimeout(2000);
    const buttons = await page.getByRole('button').allTextContents();
    console.log('Available buttons:', buttons);

    // 2. Connect the Mock Wallet
    await page.getByRole('button', { name: 'Connect Mock Connector' }).click();

    // Wait for the Disconnect button to appear showing connection is successful
    await expect(page.getByRole('button', { name: 'Disconnect' })).toBeVisible({ timeout: 10000 });

    // 3. Generate Local Identity
    await page.getByRole('button', { name: 'Generate Local Identity' }).click();
    await expect(page.getByText('Identity Ready')).toBeVisible();

    // 4. Register
    await page.getByRole('button', { name: 'Submit Commitment On-chain' }).click();
    await expect(page.getByText('Transaction confirmed!')).toBeVisible({ timeout: 15000 });

    // 5. Admin - Start Voting
    await page.getByRole('button', { name: 'Start Voting' }).click();
    await expect(page.getByText('Transaction confirmed!')).toBeVisible({ timeout: 15000 });
    await expect(page.locator('.border-fuchsia-500', { hasText: 'Voting' })).toBeVisible({ timeout: 15000 });

    // 6. Vote for Candidate A
    await page.getByRole('button', { name: 'Generate Proof & Vote' }).click();
    // Wait for vote to register, text might briefly show Heavy computation
    await expect(page.getByText('Voted Successfully! Your anonymity is guaranteed.')).toBeVisible({ timeout: 15000 });

    // 7. Admin - Close & Draw
    await page.getByRole('button', { name: 'Close & Draw Lottery' }).click();

    // Wait for the Lottery Results to appear
    await expect(page.getByText('🎉 Lottery Results')).toBeVisible({ timeout: 15000 });

    // 8. Claim Prize
    // We should see "You won! Provide a fresh address:" because we're the only voter
    await expect(page.getByText('You won! Provide a fresh address:')).toBeVisible();
    await page.getByPlaceholder('0x...').fill('0x1234567890123456789012345678901234567890');
    await page.getByRole('button', { name: 'Verify & Claim Prize' }).click();

    await expect(page.getByText('Prize Claimed successfully to your new anonymous address!')).toBeVisible({ timeout: 15000 });
});
