---
name: Overlay artifacts and tiling
description: Versioned HTML bundles, local srcdoc isolation, and content-addressed EYG viewers and layouts.
---

# Overlay artifacts and tiling

## Proposal

Overlay artifacts are named, versioned bundles of files, rendered locally in the
browser. They need no deployment, sandbox domain, or per-artifact server. The
agent fetches data using the existing `Fetch` effect and includes that data in a
bundle; artifact JavaScript never receives provider credentials or a general
bridge to Overlay's effects.

Two new browser-Overlay effects are necessary: existing effects cannot retain a
versioned document or place an interactive view in the workspace. `Artifact`
stores a complete snapshot; `Show` places a view. These are general-purpose
document/presentation operations, independent of maps, transport, or a layout.

### Effect contract

```eyg
let saved = perform Artifact({
  name: "map",
  bundle: [{
    path: "index.html",
    media_type: "text/html",
    content: !string_to_binary("<h1>My map</h1>")
  }]
})
perform Show({
  item: Artifact("map"),
  origin: {x: 0, y: 0},
  size: {x: 600, y: 1000}
})
```

`Artifact` returns `Ok(version)` or `Error(reason)`. Every successful call
appends an immutable snapshot, including repeated identical content. Versions
start at 1 independently for each name. Bundles must have a UTF-8 `index.html`,
unique relative paths, and explicit media types. File contents are binary, so
images and other assets do not require a separate file representation.
Current limits are 128 files and 2 MiB of file contents per snapshot, and
16 MiB of retained file contents across the session. Rejected saves do not
create a revision.

`Show` returns `Ok({})` or `Error(reason)`. Points use integer workspace units:
the whole canvas is 1000 by 1000, independent of screen size. Rectangles must be
positive and contained in that canvas. Repeating `Show` for the same item moves
or resizes its existing panel. Different item kinds can coexist:

- `Artifact(name)` follows the latest snapshot.
- `Revision({name, version})` pins a snapshot.
- `History(name)` lists all snapshots and their files.
- `Diff({name, from, to})` compares two snapshot numbers, displaying added,
  removed and changed files, with text changes and binary metadata.

History/diffs are rendered as escaped application UI, never as executable HTML.
History entries can be opened as pinned previews. Closing a panel does not
delete its artifact. State is retained across agent turns in this browser
session; reload persistence is outside this first implementation.

### Local srcdoc wrapper

```text
overlay_public
  └─ trusted wrapper iframe (srcdoc, sandbox="allow-scripts")
       └─ artifact iframe (srcdoc, sandbox="allow-scripts")
```

Neither frame grants `allow-same-origin`, popups, forms, downloads, or ancestor
navigation. The inner document has a distinct opaque origin and cannot read
the wrapper or application DOM, cookies, session storage, local storage, or
IndexedDB. No message bridge is exposed.

The fixed wrapper puts its CSP before all content. It allows inline scripts and
styles and embedded `data:` resources, denies connections, objects, workers,
base URLs and form actions, and sets `frame-src 'none'`. The inner `srcdoc` is
allowed, but network navigation of the inner frame is blocked by its parent's
policy. The policy therefore lives outside the artifact document. Additional
artifact CSP policies can only restrict it further. The inner HTML is escaped
as an attribute value, never interpolated as wrapper markup.

All `srcdoc` documents inherit the application's CSP. Deployment must keep that
policy compatible with artifact execution; this design cannot weaken an
existing host CSP. This is origin/storage isolation, not CPU/memory isolation.

### Bundle preparation

Use an inert HTML template to parse the entrypoint. Resolve local resources
against the bundle, convert assets to data URLs, inline linked stylesheets,
and resolve CSS asset URLs with a CSS parser. Classic external scripts become
embedded data URLs. Standalone module scripts are possible, but arbitrary
module graphs, workers, service workers, runtime relative `fetch`, and multi-page
navigation are not a virtual filesystem: bundle those applications first.
Use `src` rather than `srcset` in this initial packager.
External network resources are blocked by CSP; fetch required data/assets in
the agent's EYG program and include them in the bundle.

Validate paths and sizes before retaining snapshots. Missing or unsupported
resources produce a visible preparation error rather than loading a URL from
the application origin. Memoize preparation by immutable bundle identity so
streaming chat updates do not reload previews.

Binary values in tool-result text are reported as `BinarySummary` with a byte
count and usage guidance, rather than base64. This is only presentation: the
interpreter and saved snapshots keep the full bytes. Fetch/decode or
fetch/create-artifact should happen in one program. Returning a video response
must not exhaust the model's context window.

### Layout modules

Layout is pure EYG, shared to the local hub by content ID:

- **Dwindle:** a binary split tree, successively subdividing the remaining tile
  and alternating horizontal and vertical splits.
- **Main and stack:** the first item occupies the main column; remaining items
  split the stack column vertically.

Both produce `{item, origin, size}` placements consumed by `Show`. Layout
modules do not need new effects. A common helper shows their placements.

### Viewers are ordinary content-addressed functions

The platform does not associate file extensions or schemas with applications.
It understands HTML bundles and generic revision metadata. Image carousels,
video players, and Bluesky lexicon viewers are ordinary EYG modules: their pure
functions accept data and return bundles. Callers reference their shared content
IDs, call the function, then use `Artifact` and `Show`. They can replace or fork
any viewer without changing the platform. Examples include a carousel of
bundled images, a video player with playback speed controls, and a viewer for
`app.bsky.feed.getAuthorFeed` JSON containing `app.bsky.feed.post` records. Data
retrieval remains in the calling program, separate from presentation.

### Verification and demonstration

Test effect decoding/type checking, version retention across turns and effect
suspension, invalid bundles/rectangles, revision selection, and file diffs.
Run browser tests against actual nested frames: scripts and bundled resources
work, storage/parent access fail, injected CSP cannot relax restrictions, and
self-navigation makes no network request. Test layout coverage, order, odd
dimensions, empty/singleton inputs, and zero-size rejection. Run the repository
EYG suite before sharing modules.

The end-to-end recording uses an actual Ollama agent and live public bus data,
with a locally generated map and arrivals panel tiled together. Credentials
are supplied only to browser session storage and omitted from recorded frames,
source files and saved transcripts. Data sources and retrieval time are visible
in the artifacts; a failed live fetch must not be represented as real arrivals.
