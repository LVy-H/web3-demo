import { defineConfig } from 'vitest/config'

// Unit tests for the pure libs in src/lib (ticket, confirmationCode, orgKeypair).
// Node environment is enough — these libs touch crypto + an injectable Storage,
// not the DOM. E2E lives separately under e2e/ (Playwright).
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
    globals: false,
  },
})
