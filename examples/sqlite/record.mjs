// Optional recording tool: pass the installed Playwright module path as argv[2].
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {demo} from './demo.mjs';

const {chromium} = await import(process.argv[2]
  ? pathToFileURL(resolve(process.argv[2])).href : '@playwright/test');
const browser = await chromium.launch({headless:true});
const context = await browser.newContext({viewport:{width:1280,height:800},
  recordVideo:{dir:new URL('./.generated/', import.meta.url).pathname, size:{width:1280,height:800}}});
const page = await context.newPage();
const session = demo();
const json = value => JSON.stringify(value, null, 2);
try {
  await page.setContent(`<!doctype html><meta charset="utf-8"><title>EYG → SQLite</title>
  <style>
  *{box-sizing:border-box}body{margin:0;padding:40px;background:#0c1220;color:#ecf1f9;font-family:system-ui}
  header{display:flex;justify-content:space-between;align-items:center;color:#69e0b3;font-size:18px}
  h1{font-size:35px;letter-spacing:-1px;margin:26px 0 8px}p{font-size:19px;color:#bac5d6;margin:0 0 28px}
  main{display:grid;grid-template-columns:1.2fr 1fr;gap:24px}section{background:#141e30;border:1px solid #2e3c52;border-radius:12px;padding:22px;height:550px}
  h2{font-size:13px;color:#69e0b3;letter-spacing:1.5px;text-transform:uppercase;margin:0 0 18px}
  pre{font:16px/1.5 ui-monospace,monospace;white-space:pre-wrap;overflow-wrap:anywhere;margin:0;color:#e5edf9}
  #right pre{font-size:19px}footer{margin-top:18px;font-size:13px;color:#8797af}
  </style><header><strong>EYG → SQLite</strong><span id="step"></span></header>
  <h1></h1><p></p><main><section id="left"><h2></h2><pre></pre></section><section id="right"><h2></h2><pre></pre></section></main>
  <footer>Live Node.js + SQLite execution · generated decoder · assertions checked at each database change</footer>`);
  const show = async (step, title, subtitle, leftTitle, left, rightTitle, right) => {
    await page.evaluate(v => {
      document.querySelector('#step').textContent = `0${v.step} / 06`;
      document.querySelector('h1').textContent = v.title;
      document.querySelector('p').textContent = v.subtitle;
      for (const side of ['left','right']) {
        document.querySelector(`#${side} h2`).textContent = v[side+'Title'];
        document.querySelector(`#${side} pre`).textContent = v[side];
      }
    }, {step,title,subtitle,leftTitle,left,rightTitle,right});
    await page.waitForTimeout(6500);
  };
  await show(1, 'A typed view over a real database', 'Rules describe inherited access; the host declares the SQLite source schema.',
    'view.eyg', session.source(), 'Stored grants', json(session.setup()));
  await show(2, 'The client follows the inferred type', 'The imperative program needs no handwritten result decoder.',
    'Generated query.d.mts', session.types(), 'Imperative caller',
    "import {run} from './.generated/query.mjs';\n\nconst rows = run(db);\n\nfor (const row of rows) {\n  console.log(row.resource, row.action);\n}\n\n// resource: string\n// action: string");
  await show(3, 'SQLite executes the joins', 'A generated client repeats snapshot rounds until no new facts appear.',
    'Generated recursive SQL', session.sql().split(';\n\n')[1], 'Execution model',
    '1. Read grants and children\n\n2. Snapshot known facts\n\n3. Run SQL joins + pure EYG heads\n\n4. Insert distinct new facts\n\n5. Repeat, then decode Out');
  await show(4, 'Recursive access, decoded automatically', 'Alice can read the project, its report, and the report’s appendix.',
    'Real SQLite file', session.path+'\n\nchildren\n  atlas → report\n  report → appendix\n\nconst rows = run(db);',
    'Returned JavaScript records', json(session.initial()));
  await show(5, 'Database changes become query results', 'The same generated client sees a new child on the next run.',
    'Imperative update', "db.prepare(\n  'INSERT INTO children VALUES (?, ?)'\n).run('atlas', 'dashboard');\n\nconst rows = run(db);",
    'Returned JavaScript records', json(session.extend()));
  await show(6, 'Revoke the grant; access disappears', 'Fresh execution removes stale derived permissions. Bob’s grant remains stored.',
    'Imperative revocation', "db.prepare(\n  'DELETE FROM grants WHERE actor = ?'\n).run('alice');\n\nconst rows = run(db);",
    'Returned JavaScript records', json(session.revoke())+'\n\nAll assertions passed.\n\nTemporary query tables cleaned up.');
  await page.screenshot({path:new URL('./.generated/demo.png', import.meta.url).pathname});
} finally {
  session.close();
  await context.close();
  await page.video().saveAs(new URL('./demo.webm', import.meta.url).pathname);
  await browser.close();
}
console.log('Recorded examples/sqlite/demo.webm');
