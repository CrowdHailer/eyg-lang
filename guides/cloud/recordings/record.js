// Record the example chat app driving an EYG cloud workspace with a real model.
// node record.js <out dir> [scene...]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');

const CHAT = 'http://localhost:8080';
const OUT = process.argv[2];
const ONLY = process.argv.slice(3);
const SIZE = { width: 1280, height: 720 };
const REPO = path.resolve(__dirname, '../../..');

function api(p, body) {
  return new Promise((resolve, reject) => {
    const req = http.request(CHAT + p, { method: body ? 'POST' : 'GET', headers: { 'content-type': 'application/json' } }, (res) => {
      let data = ''; res.on('data', (c) => data += c); res.on('end', () => { try { resolve(JSON.parse(data)) } catch (e) { reject(e) } });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}
async function channelId(name) { return (await api('/api/channels')).find(c => c.name === name).id; }
async function messages(name) { return api('/api/messages?channel=' + await channelId(name)); }
// Wait for a new message by the cloud bot in a channel, optionally in a thread.
async function waitForBot(name, after, thread, timeout = 180000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const found = (await messages(name)).filter(m => m.author.bot && Number(m.id.slice(1)) > after && (thread === undefined || m.thread === thread));
    if (found.length) return found[found.length - 1];
    await sleep(1000);
  }
  throw new Error('no reply in #' + name);
}
async function lastId(name) {
  const all = await messages(name);
  return all.length ? Number(all[all.length - 1].id.slice(1)) : 0;
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// Deliver a GitHub webhook to the cloud, signed with the example workspace's webhook secret.
const CLOUD = 'http://localhost:8081';
const WEBHOOK_SECRET = process.env.GITHUB_WEBHOOK_SECRET || 'demo-webhook-secret';
let deliveries = 0;
function webhook(kind, payload) {
  const body = typeof payload === 'string' ? payload : JSON.stringify(payload);
  const signature = 'sha256=' + crypto.createHmac('sha256', WEBHOOK_SECRET).update(body).digest('hex');
  return new Promise((resolve, reject) => {
    const req = http.request(CLOUD + '/connections/github/webhook', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-github-event': kind, 'x-github-delivery': 'recording-' + Date.now() + '-' + (deliveries++), 'x-hub-signature-256': signature },
    }, (res) => { let data = ''; res.on('data', (c) => data += c); res.on('end', () => res.statusCode === 202 ? resolve(data) : reject(new Error(data))); });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}
const sample = (name) => fs.readFileSync(path.join(REPO, 'examples/cloud/webhooks', name + '.json'), 'utf8');
function comment(body) {
  return {
    action: 'created',
    issue: { number: 412, title: 'Parser rejects trailing comma in record update' },
    comment: { body, html_url: 'https://github.com/CrowdHailer/eyg-lang/issues/412#issuecomment-1' },
    repository: { full_name: 'CrowdHailer/eyg-lang' },
    sender: { login: 'octocat' },
  };
}
// The lines of a file between two markers, for showing part of workspace.eyg.
function excerpt(file, from, to) {
  const lines = fs.readFileSync(path.join(REPO, file), 'utf8').split('\n');
  const start = lines.findIndex(l => l.includes(from));
  const end = to ? lines.findIndex((l, i) => i > start && l.includes(to)) : lines.length;
  return lines.slice(start, end === -1 ? lines.length : end).join('\n');
}
async function scrollToText(page, text) {
  await page.evaluate((text) => {
    const line = [...document.querySelectorAll('pre .l')].find(l => l.textContent.includes(text));
    if (line) window.scrollTo({ top: line.getBoundingClientRect().top + window.scrollY - 90, behavior: 'smooth' });
  }, text);
}

const CAPTION = `
window.caption = (text) => {
  let el = document.getElementById('demo-caption');
  if (!el) {
    el = document.createElement('div');
    el.id = 'demo-caption';
    el.style.cssText = 'position:fixed;left:50%;top:6px;pointer-events:none;transform:translateX(-50%);max-width:80%;background:rgba(20,20,30,.88);color:#fff;font:600 18px/1.4 -apple-system,sans-serif;padding:10px 18px;border-radius:10px;z-index:9999;box-shadow:0 4px 18px rgba(0,0,0,.3);text-align:center';
    document.body.append(el);
  }
  el.textContent = text;
  el.style.display = text ? 'block' : 'none';
};`;

async function caption(page, text, hold = 2500) {
  await page.evaluate((t) => window.caption(t), text);
  await sleep(hold);
}

async function openChannel(page, name, user = 'alice') {
  await page.goto(`${CHAT}/?channel=${name}&name=${user}`);
  await page.waitForSelector('.message, form');
  await sleep(800);
}
async function send(page, text, selector = '#text') {
  await page.click(selector);
  if (text.includes('\n')) {
    await page.fill(selector, text);
    await sleep(600);
    await page.focus(selector);
    await page.keyboard.press('Enter');
  } else {
    await page.type(selector, text, { delay: 18 });
    await page.keyboard.press('Enter');
  }
  await sleep(1000);
}
async function react(page, messageText, emoji) {
  const message = page.locator('.messages .message', { hasText: messageText }).last();
  await message.hover();
  await sleep(500);
  await message.locator(`[data-emoji="${emoji}"]`).click();
  await sleep(800);
}
async function openThread(page, messageText) {
  const message = page.locator('#messages .message', { hasText: messageText }).last();
  await message.locator('.replies').click();
  await sleep(1200);
}

// The web shell, a live view inside a lustre-server-component element.
async function shellRun(page, code, wait = 60000) {
  const cells = page.locator('lustre-server-component .cell');
  const before = await cells.count();
  const input = page.locator('lustre-server-component textarea');
  await input.click();
  await input.type(code, { delay: 12 });
  await sleep(400);
  await page.keyboard.press('Control+Enter');
  const start = Date.now();
  while (await cells.count() === before && Date.now() - start < wait) await sleep(250);
  await sleep(600);
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
}
async function signIn(page, name) {
  await page.goto(CLOUD + '/login');
  await page.type('input[name=name]', name, { delay: 40 });
  await page.click('button');
  await page.waitForSelector('lustre-server-component textarea');
  await sleep(800);
}

function codePage(title, files) {
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const lines = (text) => text.split('\n').map(l => `<div class="l">${esc(l) || ' '}</div>`).join('');
  const sections = files.map(([name, text]) => `<h2>${esc(name)}</h2><pre>${lines(text)}</pre>`).join('');
  const html = `<!doctype html><meta charset="utf-8"><title>${title}</title>
<style>body{margin:0;font:15px/1.5 -apple-system,sans-serif;background:#1e1e2e;color:#cdd6f4;padding:24px 48px 120px}
h1{font-size:24px;color:#f5c2e7}h2{font-size:16px;color:#89b4fa;margin-top:28px}
pre{background:#11111b;border-radius:8px;padding:16px;font:13.5px/1.45 ui-monospace,Menlo,monospace;white-space:pre-wrap}</style>
<h1>${title}</h1>${sections}`;
  const file = path.join(OUT, 'config.html');
  fs.writeFileSync(file, html);
  return 'file://' + file;
}

const scenes = {
  async configuration(page) {
    const read = (p) => fs.readFileSync(path.join(REPO, p), 'utf8');
    await page.goto(codePage('An EYG cloud workspace is configured in EYG', [
      ['examples/cloud/workspace.eyg', read('examples/cloud/workspace.eyg')],
      ['eyg_packages/cloud/shell.eyg (channel shell helpers)', read('eyg_packages/cloud/shell.eyg').split('\n').slice(0, 75).join('\n')],
      ['examples/cloud/files/skills/triggers/SKILL.md', read('examples/cloud/files/skills/triggers/SKILL.md')],
    ]));
    await caption(page, 'workspace.eyg configures the model, secrets, connections, crons and a channel_shell policy per channel', 5000);
    for (const [line, text] of [
      ['Network secrets', 'Network secrets: programs see a hash from Env, Fetch to httpbin.org gets the real token'],
      ['React with :books:', 'A :books: reaction trigger runs a script that delegates to a subagent'],
      ['GitHub events go to #dev', 'Triggers: a pure pattern from event to boolean and a script, both EYG functions'],
      ['connections: [', 'Connections: the chat, GitHub, Bluesky, feeds, Hacker News and Lobsters'],
      ['channel: cloud.channels.named', 'Each channel gets a channel_shell, here #general and #links can write only to their directories'],
      ['Every effect available on the cloud', 'Shell helpers are ordinary EYG, a gate per effect returns Pass or Mock'],
      ['name: triggers', 'Skills start in the shared file system, agents get an index of them'],
    ]) {
      await scrollToText(page, line);
      await caption(page, text, 5000);
    }
  },

  async agent(page) {
    await openChannel(page, 'general');
    await caption(page, 'Every message goes to the channel\'s agent, it must choose to Post a reply');
    let after = await lastId('general');
    await send(page, 'Hi! In one sentence, what can you do for us here?');
    await caption(page, 'The agent works by running EYG programs, its replies are only seen if it runs Post', 1000);
    await waitForBot('general', after);
    await caption(page, 'It chose to post', 3500);
    after = await lastId('general');
    await send(page, 'bob, are we still on for lunch at 1?');
    await caption(page, 'A message between people: the agent sees it and chooses to stay silent', 15000);
    await caption(page, '', 500);
  },

  async shell(page) {
    await openChannel(page, 'random');
    await caption(page, 'A message that is an eyg code block runs directly with the channel shell');
    let after = await lastId('random');
    await send(page, '```eyg\n!int_add(20, 22)\n```');
    await waitForBot('random', after);
    await openThread(page, 'int_add');
    await caption(page, 'The result is posted in the thread', 3000);
    after = await lastId('random');
    await send(page, '```eyg\nperform Fetch({method: GET({}), scheme: HTTPS({}), host: "example.com", port: None({}), path: "/", query: None({}), headers: [], body: !string_to_binary("")})\n```');
    await waitForBot('random', after);
    await openThread(page, 'example.com');
    await caption(page, '#random\'s channel shell is offline, its fetch gate refuses', 4000);
    after = await lastId('random');
    await send(page, '```eyg\nperform WriteFile({path: "/skills/new.md", contents: !string_to_binary("hi")})\n```');
    await waitForBot('random', after);
    await openThread(page, 'skills/new.md');
    await caption(page, 'It can only write under /channels/random in the shared file system', 4000);
  },

  async secrets(page) {
    await openChannel(page, 'general');
    await caption(page, 'Secrets are stored per workspace, programs never see their value');
    let after = await lastId('general');
    await send(page, '```eyg\nperform Env("DEMO_TOKEN")\n```');
    await waitForBot('general', after);
    await openThread(page, 'Env("DEMO_TOKEN")');
    await caption(page, 'Env returns a placeholder: a hash of the secret', 4000);
    after = await lastId('general');
    await send(page, '```eyg\nlet request = {method: GET({}), scheme: HTTPS({}), host: "httpbin.org", port: None({}), path: "/headers", query: None({}), headers: [], body: !string_to_binary("")}\nmatch perform Fetch(request) {\n  Ok(response) -> { !string_from_binary(response.body) }\n  Error(reason) -> { Error(reason) }\n}\n```');
    await waitForBot('general', after);
    await openThread(page, 'httpbin.org');
    await caption(page, 'The fetch policy added the real token for httpbin.org, which echoes the headers', 5000);
  },

  async trigger(page) {
    await openChannel(page, 'links', 'bob');
    await caption(page, '#links has a trigger: a :books: reaction summarises the links in a message');
    let after = await lastId('links');
    await send(page, 'Worth a read: https://gleam.run and https://example.com');
    await caption(page, 'The agent sees the message and stays quiet, #links\'s readme says only to answer questions', 6000);
    await react(page, 'Worth a read', 'books');
    await caption(page, 'The trigger delegates to a subagent with the channel shell, it fetches the pages', 1000);
    await waitForBot('links', after);
    await openThread(page, 'Worth a read');
    await caption(page, 'The summary is posted in the message\'s thread', 6000);
  },

  async triggers_by_agent(page) {
    await openChannel(page, 'general');
    await caption(page, 'Agents can install, stop and delete triggers in their channel');
    let after = await lastId('general');
    await send(page, 'Please add a trigger here: whenever someone writes "ship it", post "Deploying now 🚀".');
    await waitForBot('general', after);
    await caption(page, 'The agent ran AddTrigger', 2500);
    after = await lastId('general');
    await send(page, 'ship it');
    await waitForBot('general', after);
    await openThread(page, 'ship it');
    await caption(page, 'The trigger posted in the thread', 3000);
    after = await lastId('general');
    await send(page, 'Please stop that deploy trigger.');
    await waitForBot('general', after);
    await caption(page, 'Stopped with StopTrigger, it can be started again or deleted', 3000);
    await send(page, 'ship it');
    await caption(page, 'A stopped trigger does nothing', 8000);
  },

  async schedules(page) {
    await openChannel(page, 'general');
    await caption(page, 'Timeouts and crons send messages to the session later, the agent decides what to post');
    let after = await lastId('general');
    await send(page, 'Remind me to stretch in 20 seconds please.');
    await waitForBot('general', after);
    await caption(page, 'The agent set a Timeout', 1000);
    after = await lastId('general');
    await waitForBot('general', after, undefined, 90000);
    await caption(page, 'When it fired the agent chose to post the reminder', 4000);
    after = await lastId('general');
    await send(page, 'Every 20 seconds post a one line fun fact about Erlang, until I say stop.');
    await waitForBot('general', after);
    after = await lastId('general');
    await waitForBot('general', after, undefined, 90000);
    await caption(page, 'A cron with a seconds field', 3000);
    after = await lastId('general');
    await send(page, 'stop the fun facts');
    await waitForBot('general', after);
    await caption(page, 'Cancelled with CancelSchedule', 4000);
  },

  async files(page) {
    await openChannel(page, 'links', 'bob');
    await caption(page, 'All channels share one file system, sessions are told when files they read change');
    let after = await lastId('links');
    await send(page, 'Which skills do you know about? Just list their names.');
    await waitForBot('links', after);
    await caption(page, 'Agents are given an index of /skills, they have read each SKILL.md', 3000);
    await openChannel(page, 'general');
    after = await lastId('general');
    await send(page, '```eyg\nperform AppendFile({path: "/skills/summarise-links/SKILL.md", contents: !string_to_binary("\\nAlways end a summary with a one word verdict: read or skip.\\n")})\n```');
    await waitForBot('general', after);
    await caption(page, '#general changed a skill, #general\'s shell may write to /skills', 3000);
    await openChannel(page, 'links', 'bob');
    after = await lastId('links');
    await send(page, 'Has anything changed in your skills?');
    await caption(page, 'The change is noted with #links\'s next message', 1000);
    await waitForBot('links', after);
    await caption(page, 'The agent was told the skill changed and re-read it', 5000);
  },

  async artifacts(page) {
    await openChannel(page, 'general');
    await caption(page, 'Artifacts: versioned HTML pages, owned by the channel that made them');
    let after = await lastId('general');
    await send(page, 'Please make an artifact called standup: an HTML page with a short agenda for today\'s standup, then post its link.');
    const reply = await waitForBot('general', after);
    await caption(page, 'The agent saved the page with the Artifact effect', 2500);
    const url = (reply.text.match(/https?:\/\/\S+/) || ['http://localhost:8081/artifacts/standup/'])[0].replace(/[).,]+$/, '');
    await page.goto(url);
    await page.addStyleTag({ content: 'body{min-height:100vh}' });
    await caption(page, 'Served by the cloud with a sandbox policy', 4000);
    await openChannel(page, 'random');
    after = await lastId('random');
    await send(page, '```eyg\nperform Artifact({name: "standup", bundle: [{path: "index.html", media_type: "text/html", content: !string_to_binary("<h1>Overwritten</h1>")}]})\n```');
    await waitForBot('random', after);
    await openThread(page, 'Overwritten');
    await caption(page, 'Another channel cannot change it', 4000);
    await openChannel(page, 'general');
    after = await lastId('general');
    await send(page, '```eyg\nperform ShareArtifact("standup")\n```');
    await waitForBot('general', after);
    await openChannel(page, 'random');
    after = await lastId('random');
    await send(page, '```eyg\nperform Artifact({name: "standup", bundle: [{path: "index.html", media_type: "text/html", content: !string_to_binary("<h1>Standup</h1><p>Shared with #random</p>")}]})\n```');
    await waitForBot('random', after);
    await openThread(page, 'Shared with #random');
    await caption(page, 'After #general shared it, #random saved version 2', 4000);
    await page.goto('http://localhost:8081/');
    await caption(page, 'Every version is kept', 3500);
  },
  async github(page) {
    await page.goto(codePage('GitHub is a connection, not a chat', [
      ['examples/cloud/workspace.eyg', excerpt('examples/cloud/workspace.eyg', 'GitHub events go to #dev', 'Stories about the languages')],
      ['connections in workspace.eyg', excerpt('examples/cloud/workspace.eyg', 'Webhooks are accepted', 'Error(_) -> { GitHub') + '\n}\n...\n' + excerpt('examples/cloud/workspace.eyg', '{name: "github"', '{')],
    ]));
    await caption(page, 'GitHub events reach the triggers of #dev, nothing posted on GitHub runs as code', 5000);
    await scrollToText(page, 'name: "merged"');
    await caption(page, 'Each pattern is a pure EYG function from the event to a boolean', 4500);
    await scrollToText(page, 'Webhooks are accepted');
    await caption(page, 'Signed webhooks arrive at /connections/github/webhook, the repository is also polled', 4500);

    await openChannel(page, 'dev');
    let after = await lastId('dev');
    await caption(page, 'A signed issues webhook arrives (sample delivery from examples/cloud/webhooks)', 1500);
    await webhook('issues', sample('issues'));
    await waitForBot('dev', after);
    await caption(page, 'triage-issues delegated to a subagent: it summarised the issue and suggested a label', 5000);
    for (const [kind, text] of [
      ['pull_request', 'A merged pull request runs the merged trigger'],
      ['star', 'A star'],
      ['workflow_run', 'CI failed on main'],
    ]) {
      after = await lastId('dev');
      await webhook(kind, sample(kind));
      await waitForBot('dev', after);
      await caption(page, text, 2500);
    }

    after = await lastId('dev');
    await caption(page, 'A comment containing EYG code arrives from GitHub', 1500);
    await webhook('issue_comment', comment('```eyg\nperform Post("posted from a GitHub comment")\n```'));
    await sleep(1500);
    await send(page, '```eyg\nmatch perform Events("github") {\n  Ok(events) -> {\n    match !list_pop(events) {\n      Ok(popped) -> { popped.head }\n      Error(_) -> { Error("empty") }\n    }\n  }\n  Error(reason) -> { Error(reason) }\n}\n```');
    await waitForBot('dev', after);
    await openThread(page, 'list_pop');
    await caption(page, 'The newest logged event is the comment: its code is only text, it never ran', 6000);

    after = await lastId('dev');
    await send(page, '```eyg\nmatch perform Events("github") {\n  Ok(events) -> {\n    !list_fold(events, {pushes: 0, issues: 0, other: 0}, (event, count) -> {\n      match event {\n        GitHubPush(_) -> { {pushes: !int_add(count.pushes, 1), ..count} }\n        GitHubIssue(_) -> { {issues: !int_add(count.issues, 1), ..count} }\n        | (_) -> { {other: !int_add(count.other, 1), ..count} }\n      }\n    })\n  }\n  Error(reason) -> { Error(reason) }\n}\n```');
    await waitForBot('dev', after);
    await openThread(page, 'pushes: 0');
    await caption(page, 'The log also holds the real eyg-lang activity found by polling the events API', 5000);
  },

  async github_by_agent(page) {
    await openChannel(page, 'dev');
    let after = await lastId('dev');
    await caption(page, 'Agents can write GitHub triggers too', 1500);
    await send(page, 'Please add a trigger here: when a GitHub issue comment mentions "regression", post a link to the comment.');
    await waitForBot('dev', after);
    await caption(page, 'The agent ran AddTrigger with a pattern over GitHubComment events', 4000);
    after = await lastId('dev');
    await webhook('issue_comment', comment('This looks like a regression from the parser change in v0.40.'));
    await waitForBot('dev', after, undefined, 60000);
    await caption(page, 'A comment mentioning "regression" arrived from GitHub and the trigger posted', 5000);
  },

  async bsky(page) {
    await page.goto(codePage('Bluesky is a connection', [
      ['connections in examples/cloud/workspace.eyg', excerpt('examples/cloud/workspace.eyg', 'name: "bsky"', 'channel: "social"')],
      ['A trigger that reads the event log', excerpt('examples/cloud/workspace.eyg', 'When Gleam posts on Bluesky', 'Webhooks are accepted')],
    ]));
    await caption(page, 'The Bluesky connection polls gleam.run and the What\'s Hot feed, events go to #social', 5000);
    await scrollToText(page, 'perform Events');
    await caption(page, 'Trigger scripts can query the log of Bluesky events with the Events effect', 5000);
    await openChannel(page, 'social');
    let after = await lastId('social');
    await caption(page, 'A trigger that posts only when an account appears in What\'s Hot again, decided from the log', 2000);
    await send(page, `\`\`\`eyg
perform AddTrigger({
  name: "hot-again",
  pattern: match {
    BskyPost(post) -> { !string_starts_with(post.source, "at://") }
    | (_) -> { False({}) }
  },
  script: match {
    BskyPost(post) -> {
      let seen = match perform Events("bsky") {
        Ok(events) -> {
          !list_fold(events, 0, (event, count) -> {
            match event {
              BskyPost(other) -> {
                match !equal(other.account, post.account) {
                  True(_) -> { !int_add(count, 1) }
                  False(_) -> { count }
                }
              }
              | (_) -> { count }
            }
          })
        }
        Error(_) -> { 0 }
      }
      match !int_compare(seen, 1) {
        Gt(_) -> {
          perform Post(!string_append("@", !string_append(post.account, !string_append(" is in What's Hot again, ", !string_append(!int_to_string(seen), !string_append(" of their posts are in the log ", post.url))))))
        }
        | (_) -> { Ok("first time") }
      }
    }
    | (_) -> { Ok("not a post") }
  }
})
\`\`\``);
    await waitForBot('social', after);
    await caption(page, 'Waiting for new posts in the feed...', 1000);
    after = await lastId('social');
    await waitForBot('social', after, undefined, 400000);
    await sleep(3000);
    await caption(page, 'The pattern matched every new post, the script queried the log and posted only for repeat accounts', 6000);
  },

  async news(page) {
    await page.goto(codePage('Feeds, Hacker News and Lobsters', [
      ['connections in examples/cloud/workspace.eyg', excerpt('examples/cloud/workspace.eyg', '{name: "blogs"', '],')],
      ['#news triggers', excerpt('examples/cloud/workspace.eyg', 'Stories about the languages', 'When Gleam posts')],
    ]));
    await caption(page, 'RSS feeds, Hacker News and Lobsters report stories to #news', 4500);
    await scrollToText(page, 'title_contains');
    await caption(page, 'Stories about Gleam or Erlang are posted, from any of the three', 4500);
    await openChannel(page, 'news');
    let after = await lastId('news');
    await send(page, `\`\`\`eyg
let take = (events, n) -> {
  !list_fold(events, {left: n, titles: []}, (event, acc) -> {
    match !int_compare(acc.left, 0) {
      Gt(_) -> {
        let title = match event {
          FeedItem(item) -> { item.title }
          HackerNewsStory(story) -> { story.title }
          LobstersStory(story) -> { story.title }
          | (_) -> { "" }
        }
        {left: !int_subtract(acc.left, 1), titles: [title, ..acc.titles]}
      }
      | (_) -> { acc }
    }
  }).titles
}
let latest = (connection) -> {
  match perform Events(connection) {
    Ok(events) -> { take(events, 3) }
    Error(reason) -> { [reason] }
  }
}
{blogs: latest("blogs"), hn: latest("hn"), lobsters: latest("lobsters")}
\`\`\``);
    await waitForBot('news', after);
    await openThread(page, 'let take');
    await caption(page, 'Every connection keeps a log, here the newest three from each', 6000);
    await page.click('#close');
    after = await lastId('news');
    await caption(page, 'A one shot trigger for the next story on Hacker News /newest', 1500);
    await send(page, `\`\`\`eyg
perform AddTrigger({
  name: "next-new-story",
  pattern: match {
    HackerNewsStory(story) -> { !equal(story.list, "new") }
    | (_) -> { False({}) }
  },
  script: match {
    HackerNewsStory(story) -> {
      let _ = perform DeleteTrigger("next-new-story")
      perform Post(!string_append("Just posted on Hacker News: ", !string_append(story.title, !string_append(" ", story.link))))
    }
    | (_) -> { Ok("") }
  }
})
\`\`\``);
    await waitForBot('news', after);
    after = await lastId('news');
    await caption(page, 'Waiting for the next poll...', 1000);
    await waitForBot('news', after, undefined, 240000);
    await caption(page, 'A new story arrived and the trigger posted it', 5000);
  },

  async web_shell(page) {
    await signIn(page, 'ada');
    await caption(page, 'ada is the first to sign in, so ada gets the admin shell. It starts unbound', 4000);
    await shellRun(page, 'perform Workspaces({})');
    await caption(page, 'The configuration API is effects: Workspaces, Connections, Channels, Secrets...', 3500);
    await shellRun(page, 'perform Connections("example")');
    await shellRun(page, 'perform Secrets("example")');
    await caption(page, 'Secret names, never values', 2500);
    await shellRun(page, 'perform WorkspaceTriggers({workspace: "example", channel: "dev"})');
    await caption(page, 'Bind to a channel to run from its point of view', 2500);
    await shellRun(page, 'perform Bind({workspace: "example", channel: "dev"})');
    await shellRun(page, 'match perform Events("github") {\n  Ok(events) -> { !list_fold(events, 0, (_event, n) -> { !int_add(n, 1) }) }\n  Error(reason) -> { -1 }\n}');
    await caption(page, 'Bound to #dev: the channel shell, its files and the events of its connections', 4000);
    await shellRun(page, 'perform Post("Hello #dev, from the web shell")');
    await caption(page, 'Posted into #dev as the channel would', 3000);

    await page.goto(CLOUD + '/admin');
    await sleep(1500);
    await caption(page, 'The admin page only uses the HTTP API, POST /api/<Effect>, gated by the same policy', 3500);
    await page.click('nav button:has-text("example")');
    await sleep(2500);
    await caption(page, 'Channels, triggers, connections, secrets and workspace.eyg, all through the API', 4000);
    await page.evaluate(() => window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' }));
    await caption(page, 'Saving workspace.eyg checks it evaluates first', 3000);

    await page.context().clearCookies();
    await signIn(page, 'bob');
    await caption(page, 'bob is not the admin: bob chooses a shell from cloud.eyg', 3500);
    await shellRun(page, 'perform Secrets("example")');
    await caption(page, 'The observer shell cannot read secret names', 3000);
    await shellRun(page, 'perform Bind({workspace: "example", channel: "general"})');
    await caption(page, 'and may only bind to #random', 3000);
    await page.locator('lustre-server-component select').selectOption('pure');
    await sleep(1200);
    await caption(page, 'Switching to the pure shell', 1500);
    await shellRun(page, 'perform Workspaces({})');
    await caption(page, 'The pure shell has no configuration API at all', 3500);
  },

  async product(page) {
    await page.goto(CLOUD + '/');
    await caption(page, 'The product page at / explains the cloud', 3500);
    await page.evaluate(() => window.scrollTo({ top: 760, behavior: 'smooth' }));
    await caption(page, 'A glossary: EYG, effects, gates, shells, dataclips', 3500);
    await page.locator('#quick-triggers').scrollIntoViewIfNeeded();
    await caption(page, 'Quick triggers: each card generates a trigger in EYG', 3500);
    const dataclip = page.locator('.card', { hasText: 'Answer from a dataclip' });
    await dataclip.scrollIntoViewIfNeeded();
    await caption(page, 'Cards for dataclips, log drains, Sentry, feeds, Bluesky and GitHub', 4000);
    const card = page.locator('.card', { hasText: 'Keyword alerts' });
    await card.scrollIntoViewIfNeeded();
    await card.locator('input').nth(1).fill('');
    await card.locator('input').nth(1).type('rust', { delay: 80 });
    await caption(page, 'The pattern and the script are both EYG functions', 3500);
    await card.locator('a', { hasText: 'Open in the shell' }).click();
    await page.waitForSelector('input[name=name]');
    await page.type('input[name=name]', 'ada', { delay: 60 });
    await caption(page, 'The first person to sign in is the admin', 2000);
    await page.click('button');
    await page.waitForSelector('lustre-server-component textarea');
    await sleep(2500);
    await caption(page, 'The shell bound to #news and holds the trigger, Ctrl+Enter installs it', 3500);
    await page.locator('lustre-server-component textarea').click();
    await page.keyboard.press('Control+Enter');
    await sleep(2500);
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await caption(page, 'Installed with #news\'s policy, the shell lists the channel\'s triggers', 4000);
    await page.goto(CLOUD + '/');
    await sleep(1500);
    await page.locator('.card', { hasText: '404s from a log drain' }).locator('.status').scrollIntoViewIfNeeded();
    await page.evaluate(() => window.scrollBy({ top: 200 }));
    await caption(page, 'Signed in, each card checks through the API that its connections are ready', 4500);
  },

  async traces(page) {
    await signIn(page, 'ada');
    await shellRun(page, 'perform Bind({workspace: "example", channel: "general"})');
    await shellRun(page, 'let _ = perform Now({})\nlet _ = perform Fetch({method: GET({}), scheme: HTTPS({}), host: "httpbin.org", port: None({}), path: "/get", query: None({}), headers: [], body: !string_to_binary("")})\nperform Post("Hello from a traced program")');
    await caption(page, 'Every program and every effect it performs is traced', 3000);
    await page.goto(CLOUD + '/admin');
    await sleep(1200);
    await page.click('text=Recent traces');
    await sleep(2000);
    await caption(page, 'eyg.run spans with an eyg.effect span per effect, and how the policy decided', 5000);
    await page.evaluate(() => window.scrollTo({ top: 600, behavior: 'smooth' }));
    await caption(page, 'Agent turns, model completions, triggers and configuration are traced too', 4500);
    await caption(page, 'Set OTEL_EXPORTER_OTLP_ENDPOINT to send the same spans to any OpenTelemetry collector', 4500);
  },

  async founders(page) {
    await openChannel(page, 'founders');
    let after = await lastId('founders');
    await caption(page, '#founders has shell.admin: its agent can use the configuration API', 2000);
    await send(page, 'Which connections does our example workspace have, and which channel does each send events to?');
    await waitForBot('founders', after);
    await caption(page, 'The agent performed Connections("example") and answered', 5000);
    after = await lastId('founders');
    await send(page, 'Which secrets are saved for it? Only the names please.');
    await waitForBot('founders', after);
    await caption(page, 'Dogfooding: the same API from an agent channel', 5000);
  },
};

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const order = ONLY.length ? ONLY : Object.keys(scenes);
  for (const name of order) {
    const context = await browser.newContext({ viewport: SIZE, recordVideo: { dir: path.join(OUT, 'raw', name), size: SIZE } });
    await context.addInitScript(CAPTION);
    const page = await context.newPage();
    const started = Date.now();
    try {
      await scenes[name](page);
      console.log('scene', name, 'ok', Math.round((Date.now() - started) / 1000) + 's');
    } catch (e) {
      console.log('scene', name, 'FAILED', e.message);
      await page.screenshot({ path: path.join(OUT, name + '-failed.png') });
    }
    await sleep(1000);
    await context.close();
  }
  await browser.close();
})();
