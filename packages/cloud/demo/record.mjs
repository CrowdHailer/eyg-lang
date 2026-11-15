// Browser integration test and reproducible recording of the real dashboard.
import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const base = process.env.EYG_CLOUD_URL || 'http://127.0.0.1:8787';
const token = process.env.EYG_CLOUD_TOKEN;
assert(token, 'Set EYG_CLOUD_TOKEN to the running demo server administrator token');
const browser = await chromium.launch({ executablePath: process.env.CHROME, headless: true, slowMo: 180 });
const context = await browser.newContext({
  viewport: { width: 1440, height: 1080 },
  recordVideo: { dir: process.env.EYG_VIDEO_DIR || '../../../research/everything-filesystem/demo', size: { width: 1440, height: 1080 } },
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
const name = `demo-${Date.now()}`;
const status = page.locator('#status');
async function field(label, value) {
  await page.getByLabel(label, { exact: true }).fill(value);
  await page.getByLabel(label, { exact: true }).press('Tab');
}
async function waitStatus(text) {
  await status.filter({ hasText: text }).waitFor({ timeout: 30_000 });
}
try {
  await page.goto(base);
  await page.getByLabel('Administrator token', { exact: true }).waitFor();
  await field('Administrator token', token);
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await waitStatus('Connected');
  await field('Box name', name);
  await page.getByLabel('Initial filesystem').selectOption('webhook-inbox');
  await page.getByRole('button', { name: 'Create box', exact: true }).click();
  await waitStatus(`Created ${name}`);
  await page.getByRole('button', { name: 'Automation', exact: true }).click();
  await page.getByRole('button', { name: 'Install webhook', exact: true }).click();
  await waitStatus('Committed');
  await field('Webhook payload', '{"event":"dashboard-demo"}');
  await page.getByRole('button', { name: 'Send test webhook', exact: true }).click();
  await waitStatus('Webhook accepted');

  const hook = await context.request.post(`${base}/app/${name}/hook`, { data: '{"event":"external-client"}' });
  assert.equal(hook.status(), 200);
  assert.equal(await hook.text(), 'Webhook accepted');
  await page.getByRole('button', { name: 'Files', exact: true }).click();
  await page.getByRole('button', { name: 'Refresh root', exact: true }).click();
  await page.getByRole('button', { name: '/data/webhooks.ndjson', exact: true }).click();
  assert.match(await page.getByLabel('File contents', { exact: true }).inputValue(), /external-client/);
  await page.waitForTimeout(1200);

  await page.getByRole('button', { name: 'Automation', exact: true }).click();
  await field('Cron name', 'heartbeat');
  await field('Cron expression (UTC)', '* * * * *');
  await page.getByRole('button', { name: 'Install cron', exact: true }).click();
  await waitStatus('Committed');
  await page.getByRole('button', { name: 'Run cron now', exact: true }).click();
  await waitStatus('{}');
  await page.getByRole('button', { name: 'Files', exact: true }).click();
  await page.getByRole('button', { name: '/data/cron.log', exact: true }).click();
  assert.match(await page.getByLabel('File contents', { exact: true }).inputValue(), /cron fired/);
  await page.waitForTimeout(1200);

  // Verify the actual scheduler, not only the manual invocation route.
  const headers = { Authorization: `Bearer ${token}` };
  const deadline = Date.now() + 75_000;
  let ticks = 0;
  while (Date.now() < deadline) {
    const response = await context.request.get(`${base}/api/boxes/${name}/files/data/cron.log`, { headers });
    ticks = (await response.text()).split('cron fired').length - 1;
    if (ticks >= 2) break;
    await page.waitForTimeout(1500);
  }
  assert(ticks >= 2, 'The automatic UTC cron must fire after the manual run');
  await page.getByRole('button', { name: 'Refresh root', exact: true }).click();
  await page.getByRole('button', { name: '/data/cron.log', exact: true }).click();
  await page.waitForTimeout(1200);

  for (const topic of ['concepts', 'api', 'getting-started', 'templates']) {
    const response = await context.request.get(`${base}/docs/${topic}`);
    assert.equal(response.status(), 200, topic);
    if (topic === 'templates') assert.match(await response.text(), /Translation catalog/);
  }
  await page.getByRole('link', { name: '20 templates', exact: true }).click();
  await page.getByText('Webhook inbox', { exact: true }).click();
  await page.waitForTimeout(1500);
  assert.deepEqual(errors, []);
  console.log(`Verified webhook, automatic cron, and documentation for ${name}`);
} catch (error) {
  console.error('Dashboard status:', await status.textContent().catch(() => 'not available'));
  console.error('Browser errors:', errors);
  throw error;
} finally {
  await context.close();
  if (process.env.EYG_VIDEO_FILE) {
    await page.video().saveAs(process.env.EYG_VIDEO_FILE);
    await page.video().delete();
    console.log(`Video: ${process.env.EYG_VIDEO_FILE}`);
  } else {
    console.log(`Video: ${await page.video().path()}`);
  }
  await browser.close();
}
