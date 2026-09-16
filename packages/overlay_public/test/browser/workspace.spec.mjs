import { test, expect } from '@playwright/test';

test('agent effects create versions, preserve active previews and expose history/diff', async ({ page }) => {
  await page.addInitScript(() => {
    if (window !== window.top) return;
    sessionStorage.setItem('overlay.llm.provider', 'ollama');
    sessionStorage.setItem('overlay.llm.model', 'qwen3.5:397b');
    sessionStorage.setItem('overlay.llm.api_key', 'browser-test-only');
  });
  const save = html => `perform Artifact({name:"map",bundle:[{path:"index.html",media_type:"text/html",content:!string_to_binary(${JSON.stringify(html)})}]})`;
  const show = (item, x, width) => `perform Show({item:${item},origin:{x:${x},y:0},size:{x:${width},y:1000}})`;
  const scripts = [
    `let _=${save('<h1>First</h1><button onclick="this.textContent=\'clicked\'">Click me</button>')} ${show('Artifact("map")',0,1000)}`,
    show('Artifact("map")',0,500),
    `let _=${save('<h1>Second</h1>')} let _=${show('History("map")',500,250)} ${show('Diff({name:"map",from:1,to:2})',750,250)}`,
  ];
  let next = 0;
  let awaitingResult = false;
  await page.route('**/api/chat', async route => {
    const message = awaitingResult
      ? { role: 'assistant', content: 'Done.', tool_calls: [] }
      : { role: 'assistant', content: '', tool_calls: [{ function: { name: 'run', arguments: { code: scripts[next++] } } }] };
    awaitingResult = !awaitingResult;
    await route.fulfill({ contentType: 'application/x-ndjson', body: JSON.stringify({ message, done: true }) + '\n' });
  });
  await page.goto('/overlay/');
  await expect(page.locator('.provider-label')).toContainText('qwen3.5');
  let turns = 0;
  async function ask() {
    turns++;
    await page.locator('textarea').fill('Update workspace');
    await page.locator('textarea').press('Enter');
    await expect.poll(() => page.locator('.message.assistant').filter({ hasText: 'Done.' }).count()).toBe(turns);
    await expect(page.locator('.layout')).toHaveAttribute('data-agent-status', 'waiting');
  }
  await ask();
  const preview = page.frameLocator('iframe.artifact-preview').frameLocator('iframe');
  await expect(preview.getByRole('heading')).toHaveText('First');
  await preview.getByRole('button').click();
  await ask();
  await expect(preview.getByRole('button')).toHaveText('clicked');
  await expect(page.locator('.artifact-panel')).toHaveAttribute('style', /width:50\.0%/);
  await ask();
  await expect(preview.getByRole('heading')).toHaveText('Second');
  await expect(page.getByText('Changed index.html')).toBeVisible();
  await page.getByRole('button', { name: 'Open v1', exact: true }).click();
  const pinned = page.frameLocator('iframe.artifact-preview[title="map · v1"]').frameLocator('iframe');
  await expect(pinned.getByRole('heading')).toHaveText('First');
  await page.getByRole('button', { name: 'Close map', exact: true }).click();
  await expect(pinned.getByRole('heading')).toHaveText('First');
});
