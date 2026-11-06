// Record the use case videos listed in usecases.md.
//
// Start the server with `gleam run`, then from this directory:
//
//     node record.js
//
// Needs Playwright with Chromium. BASE overrides http://127.0.0.1:8787.

const { chromium } = require("playwright");
const fs = require("fs");
const os = require("os");
const path = require("path");

const base = process.env.BASE || "http://127.0.0.1:8787";
const size = { width: 1280, height: 720 };

// A caption and the keys pressed, kept across page loads.
const overlayScript = () => {
  const box = (id, css) => {
    let element = document.getElementById(id);
    if (!element) {
      element = document.createElement("div");
      element.id = id;
      element.style.cssText =
        "position:fixed;z-index:9999;pointer-events:none;border-radius:8px;" +
        "font:600 15px system-ui,sans-serif;box-shadow:0 4px 16px #0004;" + css;
      document.body.appendChild(element);
    }
    return element;
  };
  const show = () => {
    if (!document.body) return;
    const caption = sessionStorage.getItem("caption");
    const keys = sessionStorage.getItem("keys");
    if (caption) {
      box("caption",
        "left:50%;top:14px;transform:translateX(-50%);max-width:80vw;text-align:center;" +
        "background:#fff7d6;color:#3d3200;border:1px solid #e6cf73;padding:8px 16px",
      ).textContent = caption;
    }
    const keyBox = box("keys",
      "right:16px;bottom:16px;background:#262a31;color:#e5c07b;border:1px solid #3b4048;" +
      "padding:6px 12px;font-family:ui-monospace,monospace");
    keyBox.textContent = keys ? "keys  " + keys : "";
    keyBox.style.display = keys ? "block" : "none";
  };
  window.__overlay = show;
  document.addEventListener("DOMContentLoaded", show);
};

const keyLabel = (key) =>
  ({ Enter: "⏎", Escape: "esc", ArrowUp: "↑", ArrowDown: "↓", ArrowLeft: "←",
     ArrowRight: "→", Backspace: "⌫", Tab: "tab", " ": "space",
     "Control+v": "ctrl+v" })[key] || key;

async function caption(page, text) {
  await page.evaluate((text) => {
    sessionStorage.setItem("caption", text);
    sessionStorage.setItem("keys", "");
    window.__overlay();
  }, text);
  await page.waitForTimeout(1400);
}

// Press keys one at a time, showing them, so the video can be followed.
async function keys(page, list, delay = 260) {
  for (const key of list) {
    await page.evaluate((label) => {
      const keys = (sessionStorage.getItem("keys") || "").split(" ").filter(Boolean);
      keys.push(label);
      sessionStorage.setItem("keys", keys.slice(-14).join(" "));
      window.__overlay();
    }, keyLabel(key));
    await page.keyboard.press(key);
    await page.waitForTimeout(delay);
  }
}

// Type a name or value into a dialog, one key per character.
const chars = (text) => [...text];

async function paste(page, code, pause = 700) {
  await page.evaluate((code) => navigator.clipboard.writeText(code), code);
  await keys(page, ["Control+v"]);
  await page.waitForTimeout(pause);
}

function terminal(page) {
  return page.locator("lustre-server-component").nth(1);
}

async function ready(page) {
  await terminal(page).locator("[data-eyg-keys]").waitFor();
  await page.waitForTimeout(700);
  await terminal(page).locator("[data-eyg-keys]").focus();
}

async function forkAt(page, text) {
  const step = terminal(page).locator(".step", { hasText: text }).first();
  await step.hover();
  await page.waitForTimeout(800);
  await Promise.all([
    page.waitForURL(/sessions\//),
    step.locator(".fork button").click(),
  ]);
  await ready(page);
}

async function dropFile(page, name, contents) {
  await page.evaluate(
    ({ name, contents }) => {
      const element = document
        .querySelectorAll("lustre-server-component")[1]
        .shadowRoot.querySelector("[data-eyg-keys]");
      const transfer = new DataTransfer();
      transfer.items.add(new File([contents], name));
      for (const type of ["dragenter", "dragover", "drop"]) {
        element.dispatchEvent(
          new DragEvent(type, { dataTransfer: transfer, bubbles: true, composed: true }),
        );
      }
    },
    { name, contents },
  );
  await page.waitForTimeout(1200);
}

// A folder on disk to mount.
function sampleProject() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cloud-project-"));
  const project = path.join(dir, "project");
  fs.mkdirSync(path.join(project, "lib"), { recursive: true });
  fs.writeFileSync(
    path.join(project, "lib", "greet.eyg"),
    '(name) -> { !string_append("Hello, ", name) }\n',
  );
  fs.writeFileSync(path.join(project, "notes.txt"), "mounted from my computer\n");
  return project;
}

async function record(name, device, script) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cloud-video-"));
  const browser = await chromium.launch();
  const viewport = (device && device.viewport) || size;
  const context = await browser.newContext({
    ...device,
    viewport,
    recordVideo: { dir, size: viewport },
    permissions: ["clipboard-read", "clipboard-write"],
  });
  await context.addInitScript(overlayScript);
  const page = await context.newPage();
  await script(page, context);
  const video = page.video();
  await context.close();
  await video.saveAs(path.join(__dirname, name + ".webm"));
  await browser.close();
  fs.rmSync(dir, { recursive: true, force: true });
}

async function editing(page) {
  await page.goto(base + "/");
  await ready(page);
  await caption(page, "1. Visiting / opens a fresh shell, ready for keys");
  await caption(page, "2. ? shows every editing key");
  await keys(page, ["?"]);
  await page.waitForTimeout(2500);
  await keys(page, ["?"]);

  await caption(page, "3. Build code with keys: n for an integer, e to assign it");
  await keys(page, ["n", "4", "0", "Enter", "e", "x", "Enter"]);
  await caption(page, "8. Enter runs the program");
  await keys(page, ["Enter"]);
  await page.waitForTimeout(600);

  await caption(page, "3. j inserts a builtin, c calls it with blanks for its arguments");
  await keys(page, ["j", ...chars("int_add"), "Enter", "c"]);
  await caption(page, "5. The status line shows what each blank needs");
  await page.waitForTimeout(1200);
  await caption(page, "4. v inserts a variable; space jumps to the next blank");
  await keys(page, ["v", "x", "Enter", " ", "n", "2", "Enter"]);
  await caption(page, "4. Arrows move the selection and a widens it");
  await keys(page, ["ArrowLeft", "ArrowLeft", "a", "a"]);
  await caption(page, "7. z undoes and Z redoes");
  await keys(page, ["z", "z", "Z", "Z"]);
  await caption(page, "9. Variables from earlier commands stay in scope");
  await keys(page, ["Enter"]);
  await page.waitForTimeout(700);

  await caption(page, "6. Paste EYG source into the selection");
  await paste(page, 'let greet = (name) -> { !string_append("Hello, ", name) }');
  await keys(page, ["Enter"]);
  await paste(page, 'greet("World")');
  await keys(page, ["Enter"]);

  await caption(page, "5. Type errors show while editing");
  await paste(page, "greet(42)", 1800);
  await caption(page, "10. Runtime errors are red with a hint, and change nothing");
  await paste(page, "missing_variable");
  await keys(page, ["Enter"]);
  await page.waitForTimeout(900);

  await caption(page, "11. ANSI colour codes in output are shown in colour");
  await paste(
    page,
    'let esc = match !string_from_binary(!binary_from_integers([27])) { Ok(s) -> { s } Error(_) -> { "" } }\n' +
      'let paint = (code, text) -> { !string_append(!string_append(esc, code), !string_append(text, !string_append(esc, "[0m"))) }\n' +
      'perform StandardOut(!string_append(paint("[32m", "green "), !string_append(paint("[1;35m", "bold magenta "), paint("[4;34m", "underlined blue\\n"))))',
  );
  await keys(page, ["Enter"]);
  await page.waitForTimeout(1200);

  await caption(page, "12. On an empty prompt, Up and Down recall earlier commands");
  await keys(page, ["ArrowUp", "ArrowUp", "ArrowUp", "ArrowDown"], 600);
  await keys(page, ["ArrowDown", "ArrowDown", "ArrowDown"], 300);

  await caption(page, "13. A running command says so, and Esc stops it");
  await paste(page, "let forever = !fix((loop) -> { (n) -> { loop(n) } })\nforever(1)");
  await keys(page, ["Enter"]);
  await page.waitForTimeout(2000);
  await keys(page, ["Escape"]);
  await page.waitForTimeout(1500);
}

async function files(page) {
  await page.goto(base + "/");
  await ready(page);
  await caption(page, "14. File effects write to the session's in-memory file system");
  await paste(
    page,
    'perform WriteFile({path: "lib/double.eyg", contents: !string_to_binary("(x) -> { !int_add(x, x) }")})',
  );
  await keys(page, ["Enter"]);
  await caption(page, "15. The root CID in the header changes with every write");
  await page.waitForTimeout(1500);
  await paste(
    page,
    'perform WriteFile({path: "lib/quad.eyg", contents: !string_to_binary("let double = import \\"./double.eyg\\"\\nlet quad = (x) -> { double(double(x)) }\\nquad")})',
  );
  await keys(page, ["Enter"]);
  await page.waitForTimeout(1200);
  await paste(
    page,
    'match perform ReadFile({path: "lib/quad.eyg", offset: 0, limit: 1000}) { Ok(b) -> { !string_from_binary(b) } Error(e) -> { Error(e) } }',
  );
  await keys(page, ["Enter"]);
  await page.waitForTimeout(1500);

  await caption(page, "16. q imports a file from the file system, tab completes");
  await keys(page, ["q", "l", "Tab", "q", "Tab", "Enter"]);
  await caption(page, "16. The import is type checked while editing");
  await keys(page, ["e", ...chars("quad"), "Enter"]);
  await page.waitForTimeout(1200);
  await keys(page, ["Enter"]);
  await caption(page, "17. quad.eyg imports ./double.eyg, relative to its own directory");
  await paste(page, "quad(10)");
  await keys(page, ["Enter"]);
  await page.waitForTimeout(1500);
}

async function mount(page) {
  await page.goto(base + "/");
  await ready(page);
  await caption(page, "18. mount folder uploads a folder from the computer");
  await terminal(page).locator("input[data-eyg-mount]").setInputFiles(sampleProject());
  await page.waitForTimeout(1500);
  await caption(page, "20. Choose where it goes; existing directories are suggested");
  await keys(page, ["Backspace", ...chars("/work"), "Enter"]);
  await page.waitForTimeout(1000);
  await caption(page, "19. Files can be dropped on the terminal too");
  await dropFile(page, "readme.txt", "dropped on the terminal\n");
  await keys(page, ["Enter"]);
  await caption(page, "21. Mounting over an existing name is refused");
  await dropFile(page, "readme.txt", "a second copy\n");
  await keys(page, ["Enter"]);
  await page.waitForTimeout(1500);
  await caption(page, "21. Choose another directory, or Esc to cancel");
  await keys(page, ["Backspace", ...chars("/copies"), "Enter"]);
  await page.waitForTimeout(1000);
  await caption(page, "22. Mounted modules can be imported");
  await keys(page, ["q", ...chars("work/project/lib/g"), "Tab", "Enter", "e", ...chars("greet"), "Enter", "Enter"]);
  await page.waitForTimeout(800);
  await paste(page, 'greet("mounted code")');
  await keys(page, ["Enter"]);
  await paste(
    page,
    'match perform ReadFile({path: "work/project/notes.txt", offset: 0, limit: 1000}) { Ok(b) -> { !string_from_binary(b) } Error(e) -> { Error(e) } }',
  );
  await keys(page, ["Enter"]);
  await page.waitForTimeout(1500);
}

async function history(page, context) {
  await page.goto(base + "/");
  await ready(page);
  await paste(page, "let x = 1");
  await keys(page, ["Enter"]);
  await paste(page, 'perform WriteFile({path: "first.txt", contents: !string_to_binary("one")})');
  await keys(page, ["Enter"]);
  await paste(page, "let x = 2");
  await keys(page, ["Enter"]);
  await paste(page, 'perform WriteFile({path: "second.txt", contents: !string_to_binary("two")})');
  await keys(page, ["Enter"]);
  const first = page.url();

  await caption(page, "23. The sidebar lists every session that has run something");
  await page.waitForTimeout(1200);
  await caption(page, "24. + New session opens a fresh shell");
  await page.locator(".new-session").click();
  await ready(page);
  await paste(page, '"another session"');
  await keys(page, ["Enter"]);
  await caption(page, "25. Reopen a past session to see its history and continue");
  await page.locator(`a[href="${new URL(first).pathname}"]`).first().click();
  await ready(page);
  await paste(page, "x");
  await keys(page, ["Enter"]);

  await caption(page, "26. A session open in two tabs stays in sync");
  const other = await context.newPage();
  await other.goto(first);
  await ready(other);
  await other.evaluate(() => navigator.clipboard.writeText('"from the other tab"'));
  await other.keyboard.press("Control+v");
  await other.waitForTimeout(400);
  await other.keyboard.press("Enter");
  await other.waitForTimeout(600);
  await other.close();
  await page.bringToFront();
  await page.waitForTimeout(1500);

  await caption(page, "27. Fork after any command: variables and files as they were then");
  await forkAt(page, "first.txt");
  await caption(page, "28. A divider marks the inherited history and links back");
  await page.waitForTimeout(1200);
  await paste(page, "x");
  await keys(page, ["Enter"]);
  await paste(page, 'perform ReadDirectory("/")');
  await keys(page, ["Enter"]);
  await page.waitForTimeout(1200);

  await caption(page, "29. The original session is unchanged");
  await terminal(page).locator(".divider a").click();
  await page.waitForURL(first);
  await ready(page);
  await page.waitForTimeout(1500);

  await caption(page, "30. Forks can be forked again");
  await page.goBack();
  await ready(page);
  await forkAt(page, "ReadDirectory");
  await caption(page, "30. The banner forks an empty session");
  await forkAt(page, "EYG shell");
  await page.waitForTimeout(1500);
}

async function phone(page) {
  await page.goto(base + "/");
  await ready(page);
  await paste(page, '"on a phone"');
  await keys(page, ["Enter"]);
  await caption(page, "31. On a phone the session list opens from the menu");
  await page.locator(".mobile-bar button").click();
  await page.waitForTimeout(2000);
  await page.keyboard.press("Escape");
  await caption(page, "31. Fork buttons are always visible on touch screens");
  await page.waitForTimeout(1500);
}

(async () => {
  const only = process.argv.slice(2);
  const videos = [
    ["editing", null, editing],
    ["files", null, files],
    ["mount", null, mount],
    ["history", null, history],
    ["phone", { viewport: { width: 390, height: 720 }, isMobile: true, hasTouch: true }, phone],
  ];
  for (const [name, device, script] of videos) {
    if (only.length && !only.includes(name)) continue;
    await record(name, device, script);
    console.log("recorded", name);
  }
})();
