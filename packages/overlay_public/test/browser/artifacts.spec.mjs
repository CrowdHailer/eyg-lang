import { test, expect } from '@playwright/test';

const file = (path, media_type, text) => ({ path, media_type, content: Buffer.from(text).toString('base64') });

async function mount(page, html, assets = []) {
  await page.goto('/overlay/');
  await page.evaluate(({ html, assets }) => {
    return import('/overlay/src/overlay/public/artifact_preview.mjs').then(({ wrapper, packageFiles }) => {
      document.cookie = 'artifact_test=secret; SameSite=Lax';
      localStorage.setItem('artifact_test', 'secret');
      sessionStorage.setItem('artifact_test', 'secret');
      const iframe = document.createElement('iframe');
      iframe.id = 'test-preview';
      iframe.sandbox = 'allow-scripts';
      iframe.srcdoc = wrapper(packageFiles([{ path: 'index.html', media_type: 'text/html', content: btoa(unescape(encodeURIComponent(html))) }, ...assets]));
      document.body.append(iframe);
    });
  }, { html, assets });
  const inner = page.frameLocator('#test-preview').frameLocator('iframe');
  await expect(inner.locator('body')).toBeAttached();
  return inner;
}

test('bundles scripts, nested CSS imports, images and inline style URLs', async ({ page }) => {
  const inner = await mount(page, '<link rel="stylesheet" href="css/main.css"><img id="image" src="image.svg"><div id="styled" style="background-image:url(image.svg)">hello</div><script src="js/main.js"></script>', [
    file('js/main.js', 'text/javascript', 'document.body.dataset.executed="yes"'),
    file('css/main.css', 'text/css', '@import "nested.css"; body {background-image:url(../image.svg)}'),
    file('css/nested.css', 'text/css', 'body {color:rgb(12, 34, 56)}'),
    file('image.svg', 'image/svg+xml', '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>'),
  ]);
  await expect(inner.locator('body')).toHaveAttribute('data-executed', 'yes');
  await expect(inner.locator('body')).toHaveCSS('color', 'rgb(12, 34, 56)');
  await expect.poll(() => inner.locator('#image').evaluate(img => img.naturalWidth)).toBe(10);
  expect(await inner.locator('#styled').evaluate(el => getComputedStyle(el).backgroundImage)).toContain('data:image/svg+xml');
});

test('opaque origin blocks storage, cookies, parent and top DOM access', async ({ page }) => {
  const inner = await mount(page, `<script>
    const attempts = {
      cookie: () => document.cookie,
      local: () => localStorage.getItem('artifact_test'),
      session: () => sessionStorage.getItem('artifact_test'),
      indexed: () => indexedDB.open('test'),
      parent: () => parent.document.body,
      top: () => top.document.body
    };
    for (const [name, attempt] of Object.entries(attempts)) {
      try { attempt(); document.body.dataset[name] = 'accessible'; }
      catch { document.body.dataset[name] = 'blocked'; }
    }
  </script>`);
  for (const key of ['cookie', 'local', 'session', 'indexed', 'parent', 'top']) {
    await expect(inner.locator('body')).toHaveAttribute(`data-${key}`, 'blocked');
  }
});

test('additional CSP and meta removal cannot permit network requests', async ({ page }) => {
  const requests = [];
  await page.route('**/artifact-leak?*', route => {
    requests.push(route.request().url());
    return route.fulfill({ status: 204, body: '' });
  });
  const inner = await mount(page, `<meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline'; connect-src *; img-src *">
    <script>
      document.querySelectorAll('meta').forEach(m => m.remove());
      fetch('http://127.0.0.1:5173/artifact-leak?fetch').catch(() => document.body.dataset.fetch='blocked');
      const img = new Image(); img.src='http://127.0.0.1:5173/artifact-leak?image';
    </script>`);
  await expect(inner.locator('body')).toHaveAttribute('data-fetch', 'blocked');
  await page.waitForTimeout(300);
  expect(requests).toEqual([]);
});

for (const navigation of ['script', 'meta', 'link', 'form']) {
  test(`wrapper blocks ${navigation} navigation before a request`, async ({ page }) => {
    const requests = [];
    await page.route('**/artifact-leak?*', route => {
      requests.push(route.request().url());
      return route.fulfill({ status: 204, body: '' });
    });
    const url = 'http://127.0.0.1:5173/artifact-leak?navigation';
    const html = {
      script: `<script>location.href='${url}'</script>`,
      meta: `<meta http-equiv="refresh" content="0;url=${url}">`,
      link: `<a href="${url}">Navigate</a>`,
      form: `<form action="${url}"><button>Navigate</button></form>`,
    }[navigation];
    const inner = await mount(page, html);
    if (navigation === 'link') await inner.getByText('Navigate').click();
    if (navigation === 'form') await inner.getByText('Navigate').click();
    await page.waitForTimeout(500);
    expect(requests).toEqual([]);
    expect(page.url()).toContain('/overlay/');
  });
}

test('wrapper attribute escaping prevents artifact markup breaking out', async ({ page }) => {
  await mount(page, `"><script>parent.document.body.dataset.escaped='yes'</script><iframe srcdoc="<p>nested</p>"></iframe>`);
  await expect(page.locator('body')).not.toHaveAttribute('data-escaped');
  const wrapper = page.frameLocator('#test-preview');
  await expect(wrapper.locator('body > iframe')).toHaveCount(1);
  await expect(wrapper.locator('script')).toHaveCount(0);
});

test('preparation rejects missing files without requesting application URLs', async ({ page }) => {
  await page.goto('/overlay/');
  const result = await page.evaluate(async () => {
    const { packageFiles } = await import('/overlay/src/overlay/public/artifact_preview.mjs');
    try { packageFiles([{path:'index.html',media_type:'text/html',content:btoa('<img src="secret.png">')}]); }
    catch (error) { return error.message; }
  });
  expect(result).toBe('Missing bundle file: secret.png');
});
