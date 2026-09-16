import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';

// Exercise the actual EYG bundle constructors, including their JavaScript in
// opaque-origin frames, rather than maintaining duplicate HTML fixtures.
function bundle(expression) {
  const code = `let json=import "./eyg_packages/eyg/json.eyg"
    let bundle=${expression}
    !list_fold(bundle,{},(file,_) -> {
      let content=match !string_from_binary(file.content) {Ok(s)->{s} Error(_)->{!never(perform Abort("test expects UTF-8"))}}
      let fields=[json.field("path",json.string(file.path)),json.field("media_type",json.string(file.media_type)),json.field("text",json.string(content))]
      perform StandardOut(!string_append(json.to_string(json.object(fields)),"\n"))
    })`;
  const directory = mkdtempSync(resolve(tmpdir(), 'overlay-viewer-'));
  try {
    const source = resolve(directory, 'test.eyg');
    writeFileSync(source, code.replaceAll('import "./eyg_packages/', `import "${resolve('../../eyg_packages')}/`));
    return execFileSync('eyg', ['run', source], { encoding: 'utf8' })
      .trim().split('\n').map(line => { const f = JSON.parse(line); return { ...f, content: Buffer.from(f.text).toString('base64') }; });
  } finally { rmSync(directory, { recursive: true }); }
}

async function mount(page, files) {
  await page.goto('/overlay/');
  await page.evaluate(async files => {
    const { wrapper, packageFiles } = await import('/overlay/src/overlay/public/artifact_preview.mjs');
    const frame = document.createElement('iframe');
    frame.id = 'viewer'; frame.sandbox = 'allow-scripts';
    frame.style = 'position:fixed;inset:0;width:100%;height:100%;background:white;z-index:100';
    frame.srcdoc = wrapper(packageFiles(files)); document.body.append(frame);
  }, files);
  return page.frameLocator('#viewer').frameLocator('iframe');
}

test('content-addressable carousel navigates and wraps images', async ({ page }) => {
  const files = bundle(`let viewer=import "./eyg_packages/artifact_viewers/carousel.eyg"
    viewer.render({title:"Route views",images:[{caption:"First",media_type:"image/svg+xml",content:!string_to_binary("<svg xmlns='http://www.w3.org/2000/svg'/>")},{caption:"Second",media_type:"image/svg+xml",content:!string_to_binary("<svg/>")}]})`);
  const frame = await mount(page, files);
  await expect(frame.locator('#position')).toHaveText('1 / 2');
  await frame.getByRole('button', { name: 'Next image' }).click();
  await expect(frame.locator('#position')).toHaveText('2 / 2');
  await expect(frame.locator('figure').nth(0)).toBeHidden();
  await frame.getByRole('button', { name: 'Next image' }).click();
  await expect(frame.locator('#position')).toHaveText('1 / 2');
  await frame.getByRole('button', { name: 'Previous image' }).click();
  await expect(frame.locator('#position')).toHaveText('2 / 2');
  await frame.locator('body').press('ArrowRight');
  await expect(frame.locator('#position')).toHaveText('1 / 2');
  await frame.locator('body').press('ArrowLeft');
  await expect(frame.locator('#position')).toHaveText('2 / 2');
});

test('carousel empty and singleton states disable navigation', async ({ page }) => {
  const empty = await mount(page, bundle('let v=import "./eyg_packages/artifact_viewers/carousel.eyg" v.render({title:"Empty",images:[]})'));
  await expect(empty.locator('#empty')).toBeVisible();
  await expect(empty.getByRole('button', { name: 'Next image' })).toBeDisabled();
  const single = await mount(page, bundle('let v=import "./eyg_packages/artifact_viewers/carousel.eyg" v.render({title:"One",images:[{caption:"Only",media_type:"image/svg+xml",content:!string_to_binary("<svg/>")}]})'));
  await expect(single.locator('#position')).toHaveText('1 / 1');
  await expect(single.getByRole('button', { name: 'Previous image' })).toBeDisabled();
});

test('video viewer speed selector changes the native player rate', async ({ page }) => {
  const files = bundle('let viewer=import "./eyg_packages/artifact_viewers/video.eyg" viewer.render({title:"Clip",media_type:"video/webm",content:!string_to_binary("")})');
  const frame = await mount(page, files);
  await frame.getByLabel('Playback speed').selectOption('2');
  expect(await frame.locator('video').evaluate(v => v.playbackRate)).toBe(2);
  await frame.getByLabel('Playback speed').selectOption('0.5');
  expect(await frame.locator('video').evaluate(v => v.playbackRate)).toBe(0.5);
});

test('Bluesky viewer renders supported lexicons as text and handles invalid feeds', async ({ page }) => {
  const feed = JSON.stringify({ feed: [{ post: { author: { handle: 'bus.example', displayName: 'Bus Company' }, record: { $type: 'app.bsky.feed.post', text: '</script><img src=x onerror="document.body.dataset.pwned=1">', createdAt: '2026-09-16T12:00:00Z' }, likeCount: 3 } }, { post: { record: { $type: 'other.lexicon', text: 'Unsupported' } } }] });
  const expression = `let viewer=import "./eyg_packages/artifact_viewers/bluesky.eyg" viewer.render({title:"Posts",feed:${JSON.stringify(feed)},retrieved_at:"2026-09-16"})`;
  const frame = await mount(page, bundle(expression));
  await expect(frame.locator('article')).toHaveCount(1);
  await expect(frame.locator('article')).toContainText('Bus Company');
  await expect(frame.locator('article p')).toHaveText('</script><img src=x onerror="document.body.dataset.pwned=1">');
  await expect(frame.locator('img')).toHaveCount(0);
  await expect(frame.locator('body')).not.toHaveAttribute('data-pwned');
  const invalid = await mount(page, bundle('let viewer=import "./eyg_packages/artifact_viewers/bluesky.eyg" viewer.render({title:"Posts",feed:"not json",retrieved_at:"now"})'));
  await expect(invalid.locator('#posts')).toContainText('Unable to display feed');
});

test('Bluesky viewer handles empty feeds, wrong schemas and attachment notices', async ({ page }) => {
  const render = feed => bundle(`let v=import "./eyg_packages/artifact_viewers/bluesky.eyg" v.render({title:"Posts",feed:${JSON.stringify(JSON.stringify(feed))},retrieved_at:"now"})`);
  let frame = await mount(page, render({ feed: [] }));
  await expect(frame.locator('#posts')).toHaveText('No supported posts in this feed.');
  frame = await mount(page, render({ other: [] }));
  await expect(frame.locator('#posts')).toContainText('Expected app.bsky.feed.getAuthorFeed response');
  frame = await mount(page, render({ feed: [{ reason: {}, post: { record: { $type: 'app.bsky.feed.post', text: 'A photo', embed: {} } } }] }));
  await expect(frame.locator('article')).toContainText('Unknown author');
  await expect(frame.locator('article')).toContainText('Reposted');
  await expect(frame.locator('article')).toContainText('does not load remote media');
});
