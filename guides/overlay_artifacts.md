---
name: Overlay artifacts
description: Create, inspect, control, save and share versioned HTML bundles in web Overlay.
---

# Overlay artifacts

The reproduction commands below generate browser recordings and a replayable
trajectory from the current source.

In web Overlay, ask the agent to build an HTML document, show it, and check its
preview. The browser retains complete revisions, and the trajectory records
`Artifact`, `Show` and `Puppet` alongside other effects.

```eyg
let saved = perform Artifact({
  name: "notebook",
  bundle: [{
    path: "index.html",
    media_type: "text/html",
    content: !string_to_binary("<h1>Field notebook</h1><p>Observations</p>")
  }]
})
perform Show({
  item: Artifact("notebook"),
  origin: {x: 0, y: 0},
  size: {x: 1000, y: 1000}
})
```

`Artifact` returns `Ok(version)` or `Error(reason)`. Each successful save appends
a complete snapshot, even if identical; versions start at 1 for each name.
Bundles require a UTF-8 `index.html`, unique relative file paths and explicit
media types. Limits are 128 files and 2 MiB per snapshot, with 16 MiB of retained
file contents per session. A rejected save creates no revision.

`Show` returns `Ok({})` or an error. Its integer coordinates cover a 1000×1000
canvas. Positive rectangles must fit inside it. Showing an existing item moves
its panel. `Artifact(name)` follows the latest revision;
`Revision({name, version})` pins one. `History(name)` lists snapshots and
`Diff({name, from, to})` compares files. History offers **Open vN** and
**Compare with previous**. Closing panels retains the snapshots; **Open** and
**History** remain available in the library.

Completed turns, layout and completed shares are saved in this tab's session
storage. Refresh restores them; closing the tab clears that storage. A running
turn can have unsaved changes. If storage is full, keep the tab open and use
**Retry saving** or **Download workspace**.

**Download workspace** includes all files, revisions and panel placements.
Open an empty, idle Overlay tab and use **Import workspace**. Imports are limited
to 32 MiB and validated before replacing the empty workspace. Portable files
omit credentials, chat and sharing ownership secrets, so an imported copy makes
independent shares.

## Preview controls

```eyg
perform Puppet({
  page: Artifact("notebook"),
  locator: [Role({role: "heading", name: "Field notebook"})],
  action: Screenshot({}),
  timeout: 5000
})
```

`Puppet` controls a shown latest or pinned preview and returns `Ok(reply)` or
`Error(reason)`. Locators narrow from the document using `Css`, `Text`, `Role`,
`Label`, `Placeholder`, `TestId`, `HasText` and `Nth`. Actions include clicking,
filling, checking, selecting, pressing, reading, expectations and screenshots.
Ambiguous locators fail; interactions wait for a visible, enabled element.
Expectations retry until the timeout. Screenshots return PNG bytes and appear
in the chat and model's tool result. The
[EYG Playwright library](../eyg_packages/playwright/README.md) wraps this contract
with `page`, `get_by_role`, `click` and `expect` functions.

Screenshots freeze a DOM clone, including forms and canvases, and render it
through SVG `foreignObject`. They retain bundled styles; hover states and inner
scroll positions are not captured. The latest three screenshots per call are
attached to the model. Other binary tool output over 1 KiB is summarized by
size; programs and archives retain its full bytes.

## Bundles, viewers and layouts

Relative images, fonts and media become data URLs; linked CSS and recursive
imports are inlined. Missing files produce a preparation error. Bundle module
graphs before saving them: previews do not provide a virtual server for runtime
relative fetches, workers or multi-page navigation. Fetch required data through
EYG effects and include it in the bundle.

[Viewer modules](../eyg_packages/artifact_viewers/README.md) build image carousels,
video players and text views of Bluesky feeds. They are ordinary EYG functions
selected by a content reference, independent of file-type dispatch. Their
browser behavior is written in Gleam and generated into the EYG bundle.
[Tiling modules](../eyg_packages/tiling/README.md) produce placements for dwindle
and main-and-stack layouts; `show(placements)` uses the same `Show` effect.

Local previews use two nested opaque-origin frames with `sandbox="allow-scripts"`.
A fixed wrapper CSP permits inline scripts/styles and embedded assets, and
blocks network, storage, forms, workers and other frames. Requests carry random
ids: the wrapper only relays the application's messages, and the preview
answers with data. Artifacts can misreport their own state. These frames provide
origin isolation; they do not impose CPU or heap limits.

## Sharing

Click **share** on a preview to publish that revision to the configured hub.
The returned public link is `/artifact/<id>`; older revisions remain available.
Sharing a newer revision links the earlier page to it. The hub verifies the
previous share's ownership secret, stores its hash and serves every file with
a sandbox CSP. `GET /artifacts/<id>` returns the bundle as JSON.

The agent has no publishing effect. Sharing secrets stay in the tab's recovery
state and are omitted from portable workspace files. Hub administrators can
[withdraw a share](../packages/hub/README.md#withdrawing-shared-artifacts).

## Reproduce the checks

Use an existing local hub, or start an isolated database:

```sh
docker run --rm -d --name eyg-artifact-db -p 127.0.0.1:15432:5432 -e POSTGRES_PASSWORD=postgres postgres:17
```

In `packages/hub`, migrate and start the hub:

```sh
export POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=15432 POSTGRES_PASSWORD=postgres
export SECRET_KEY_BASE=artifact-local-development PORT=7812
gleam dev migrate
gleam run
```

In `packages/overlay_puppet`, regenerate the preview and viewer bundles with
`gleam run --runtime bun -m bundle`. Install the browser recording dependencies
with `bun install` in `packages/tracing`; use `bunx playwright install
chromium` if Chromium is not installed.

Start Overlay in `packages/overlay_public`:

```sh
EYG_HUB=http://127.0.0.1:7812 EYG_OLLAMA=http://127.0.0.1:7201 bun run dev -- --port 5280
```

With the hub listening on 7812, run these in `packages/tracing`:

```sh
gleam run --runtime bun -m tracing/artifact_demo
gleam run --runtime bun -m tracing/viewer_demo
```

They start/stop a scripted model, use real browser previews and real hub shares,
and save videos, screenshots and a replayable trajectory under `recordings`.
Set `CHROME_BIN` for an existing Chromium executable. Use
`DEMO_OUTPUT_DIR=.recordings/recheck` to keep a separate validation run.
Run `eyg script entry.eyg` at the repository root to check the EYG libraries.
Stop the local hub/Overlay processes after testing, and remove this temporary
database with `docker stop eyg-artifact-db`.
