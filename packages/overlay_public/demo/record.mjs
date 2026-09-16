// Run with OLLAMA_API_KEY in the environment. It is never written to the
// transcript or typed into the recorded UI. No mocked model/data responses.
import { chromium } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const key = process.env.OLLAMA_API_KEY;
if (!key) throw new Error('Set OLLAMA_API_KEY');
const origin = process.env.OVERLAY_URL || 'http://127.0.0.1:5173';
const reference = process.env.ARTIFACT_CONTEXT || 'baguqeera5huasaub27uqjbwbdqqf3ulww6nsljgfc65uxiqhsfkysm7zxaxq';
const out = resolve(process.env.RECORDING_DIR || 'recordings');
await mkdir(out, { recursive: true });
const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1600, height: 1000 },
  recordVideo: { dir: resolve(out, 'raw'), size: { width: 1600, height: 1000 } },
});
await context.addInitScript(({ key, model }) => {
  if (window !== window.top) return;
  sessionStorage.setItem('overlay.llm.provider', 'ollama');
  sessionStorage.setItem('overlay.llm.model', model);
  sessionStorage.setItem('overlay.llm.api_key', key);
}, { key, model: process.env.OLLAMA_MODEL || 'qwen3.5:397b' });
const page = await context.newPage();
const transcript = [];
const network = [];
let completed = false;
page.on('response', async response => {
  const url = response.url();
  if (url.includes('/api/chat')) {
    try {
      const text = await response.text();
      const chunks = text.trim().split('\n').map(line => JSON.parse(line));
      transcript.push({ at: new Date().toISOString(), chunks });
      const calls = chunks.flatMap(c => c.message?.tool_calls || []);
      console.log('Model response', response.status(), calls.map(c => c.function?.name).join(',') || 'text');
      await writeFile(resolve(out, 'agent-transcript.json'), JSON.stringify({ transcript, network }, null, 2));
    } catch { console.log('Unable to read model response', response.status()); }
  } else if (/api\.tfl\.gov\.uk|public\.api\.bsky\.app|cc0-videos/.test(url)) {
    network.push({ at: new Date().toISOString(), url, status: response.status() });
    console.log('Data', response.status(), url);
  }
});
page.on('pageerror', error => console.log('Page error:', error.message));

async function ask(prompt, consumesData = false) {
  if (consumesData) prompt += ' Use context.network.text/bytes to fetch and consume the result in this same run. Use context.concat([parts]) to assemble HTML. Return only the small Artifact/Show result, never raw data or a bundle. Do not copy data from chat or invent timestamps.';
  console.log('Prompt:', prompt);
  transcript.push({ prompt, at: new Date().toISOString() });
  await page.locator('textarea').fill(prompt);
  await page.locator('textarea').press('Enter');
  await page.waitForFunction(() => document.querySelector('.layout')?.dataset.agentStatus !== 'waiting');
  await page.waitForFunction(() => document.querySelector('.layout')?.dataset.agentStatus === 'waiting', { }, { timeout: 900_000 });
  const errors = await page.locator('.failure-message').allTextContents();
  if (errors.some(e => e.trim())) throw new Error(errors.join('\n'));
  console.log('Finished turn; panels:', await page.locator('.artifact-heading span').allTextContents());
  await page.waitForTimeout(2500);
  await writeFile(resolve(out, 'agent-transcript.json'), JSON.stringify({ transcript, network }, null, 2));
}

try {
  await page.goto(`${origin}/overlay/?reference=${reference}`);
  await page.waitForSelector('.context.ready');
  await ask('Prepare for a bus-workspace demo. Read the syntax guide using context.network.text("eyg.run","/guides/eyg-syntax-guide.md",None({})), and return the context.network.readme and all five layout/viewer readmes so you know their exact APIs. Do not create anything yet.');
  await ask('Create an attractive original SVG schematic map for London bus stop 490008660N. Use this EYG structure: let data = context.network.text("api.tfl.gov.uk", "/StopPoint/490008660N", None({})) then let html = context.concat([YOUR_HTML_PARTS_AND_DATA]) then let _ = perform Artifact({name:"map",bundle:[{path:"index.html",media_type:"text/html",content:!string_to_binary(html)}]}) then perform Show({item:Artifact("map"),origin:{x:0,y:0},size:{x:1000,y:1000}}). Separate let bindings with newlines, not semicolons; do not write match or perform Fetch, because network.text handles this. Fill the HTML parts with your own SVG map. Embed data in a script type=application/json (escape < using !string_replace), and use JavaScript JSON.parse to select children.find(c=>c.id==="490008660N") and display that stop name and coordinates. Label it schematic and cite TfL.', true);
  if (await page.locator('iframe.artifact-preview[title="map"]').count() !== 1) throw new Error('Agent did not show a map');
  await ask('Create a readable live buses artifact with the same EYG structure: let data=context.network.text("api.tfl.gov.uk","/StopPoint/490008660N/Arrivals",None({})) then assemble your HTML with context.concat, then perform Artifact, then context.main_stack.show(context.main_stack.layout([Artifact("map"),Artifact("buses")],{origin:{x:0,y:0},size:{x:1000,y:1000}},550)). Do not manually implement Fetch or error matches. In the HTML JavaScript, sort actual JSON by timeToStation. timeToStation is SECONDS: display Math.ceil(arrival.timeToStation / 60) + " min". Use arrival.platformName (not platform). Display the actual API timestamp and source. Give each displayed row data-arrival and data-seconds attributes, with a child class="eta" showing the minutes. Use textContent for API text. Save as buses. Execute now.', true);
  await ask('Fetch the latest three Reading Buses posts from public.api.bsky.app /xrpc/app.bsky.feed.getAuthorFeed with Some("actor=reading-buses.co.uk&limit=3"). Use context.bluesky.render with the real JSON, title "Reading Buses · separate operator", and retrieved_at: !int_to_string(perform Now({})). Save as posts. This is a separate operator from the London stop. Use no hardcoded date.', true);
  await ask('Create two original SVG route illustrations for routes 214 and 88. Use context.carousel.render to build an image carousel with suitable captions. Save it as carousel. Do not fetch external images. Keep the response short.');
  await ask('Fetch interactive-examples.mdn.mozilla.net /media/cc0-videos/flower.webm using context.network.bytes. Immediately pass the binary to context.video.render({title:"CC0 flower · sample clip",media_type:"video/webm",content:bytes}) and save as video. This is sample footage, not bus footage. Then tile [Artifact("map"),Artifact("buses"),Artifact("posts"),Artifact("carousel"),Artifact("video")] with context.dwindle. Execute now.', true);
  await ask('Now rearrange all five artifacts with context.main_stack, map as the main tile and buses, posts, carousel, video in the stack. Use a 500 main share. Do not re-fetch the data or re-create the artifacts.');

  const busFrame = page.locator('.artifact-panel').filter({ has: page.locator('.artifact-heading span', { hasText: /^buses$/ }) }).frameLocator('iframe.artifact-preview').frameLocator('iframe');
  let validArrivals = false;
  for (let attempt = 0; attempt < 4; attempt++) {
    const rows = await busFrame.locator('[data-arrival]').evaluateAll(rows => rows.map(row => ({ seconds: Number(row.dataset.seconds), eta: row.querySelector('.eta')?.textContent })));
    console.log('Arrival verification:', JSON.stringify(rows));
    validArrivals = rows.length > 0 && rows.every(row => Number.isFinite(row.seconds) && /^\s*\d+\s*min\s*$/.test(row.eta || '') && Number.parseInt(row.eta) === Math.ceil(row.seconds / 60));
    if (validArrivals) break;
    if (attempt === 3) break;
    const visible = await busFrame.locator('body').innerText();
    await ask(`Correct the buses artifact before we finish. Browser verification found ${JSON.stringify(rows)}; visible text: ${visible.slice(0, 1500)}. Fetch fresh arrivals and regenerate the buses HTML. Each row MUST have data-arrival and data-seconds=String(arrival.timeToStation); a child with class eta MUST use textContent=Math.ceil(arrival.timeToStation/60)+' min'. Include source timestamp. Use the existing EYG context.network.text helper. Save under buses; keep its existing layout. This is a real correction, not a mock.`, true);
  }
  if (!validArrivals) throw new Error('Arrival minutes did not match source seconds');

  const carousel = page.locator('.artifact-panel').filter({ has: page.locator('.artifact-heading span', { hasText: /^carousel$/ }) });
  const carouselFrame = carousel.frameLocator('iframe.artifact-preview').frameLocator('iframe');
  await carouselFrame.getByRole('button', { name: 'Next image' }).click();
  await page.waitForTimeout(2000);
  await carouselFrame.getByRole('button', { name: 'Previous image' }).click();
  const video = page.locator('.artifact-panel').filter({ has: page.locator('.artifact-heading span', { hasText: /^video$/ }) });
  const videoFrame = video.frameLocator('iframe.artifact-preview').frameLocator('iframe');
  await videoFrame.getByLabel('Playback speed').selectOption('2');
  await videoFrame.locator('video').evaluate(video => video.play());
  await page.waitForTimeout(5000);
  await page.screenshot({ path: resolve(out, 'workspace.png'), fullPage: true });
  // Close unrelated panels through the ordinary UI so the three-item history
  // layout has a clear canvas. Closing preserves their stored bundles.
  const names = await page.locator('.artifact-heading span').allTextContents();
  for (const name of names.filter(name => name !== 'map')) {
    await page.getByRole('button', { name: `Close ${name}`, exact: true }).click();
  }
  await ask('Create a new version of map with a visibly updated title and appearance, fetching the actual stop data again to retain its correct name and coordinates. Use the version number returned by Artifact: show a Diff from that number minus 1 to the new number, History("map"), and Artifact("map") using context.main_stack. All unrelated panels have been closed; keep their stored bundles. Execute now.', true);
  await page.waitForTimeout(5000);
  await page.screenshot({ path: resolve(out, 'history.png'), fullPage: true });
  completed = true;
} finally {
  await writeFile(resolve(out, 'agent-transcript.json'), JSON.stringify({ transcript, network }, null, 2));
  await context.close();
  const filename = completed ? 'artifacts-demo.webm' : 'artifacts-incomplete.webm';
  await page.video().saveAs(resolve(out, filename));
  await browser.close();
  console.log('Recording saved to', resolve(out, filename));
}
