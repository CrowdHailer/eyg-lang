import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './test/browser',
  timeout: 30_000,
  use: {
    baseURL: 'http://127.0.0.1:5173',
    launchOptions: { executablePath: process.env.CHROMIUM_PATH },
  },
  webServer: {
    command: 'bun --bun run dev -- --host 127.0.0.1',
    url: 'http://127.0.0.1:5173/overlay/',
    reuseExistingServer: !process.env.CI,
  },
});
