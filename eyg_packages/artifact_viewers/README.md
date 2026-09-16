# Viewers are functions

The web platform displays HTML bundles. It does not select applications based
on file types. These pure EYG functions are three replaceable example
applications, each shareable by content ID with its own `readme` field.

| Module | Function input | Output |
| --- | --- | --- |
| `carousel.eyg` | `{title, images: [{caption, media_type, content}]}` | Image carousel with buttons, keyboard navigation and captions |
| `video.eyg` | `{title, media_type, content}` | Native video player with explicit playback-speed controls |
| `bluesky.eyg` | `{title, feed, retrieved_at}` | Text viewer for `app.bsky.feed.getAuthorFeed` / `app.bsky.feed.post` |

Titles/captions are strings, image/video contents are binary, and `feed` is the
UTF-8 JSON response string. All `render` functions return a bundle: a list of
`{path, media_type, content}` records, including `index.html`. Call `Artifact`
to store it and `Show` to display it. Fetching data and selecting a layout are
the caller's responsibility. No viewer performs network or storage effects.

```eyg
let viewer = import "./carousel.eyg"
let bundle = viewer.render({
  title: "Route views",
  images: [{
    caption: "A locally generated map",
    media_type: "image/svg+xml",
    content: !string_to_binary("<svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'><circle cx='50' cy='50' r='30' fill='teal'/></svg>")
  }]
})
perform Artifact({name: "route-views", bundle})
```

The Bluesky example deliberately supports text posts only. It identifies
unsupported attachments without loading external media, skips other lexicons,
and displays empty/malformed input states. Remote text uses `textContent` and
JSON cannot terminate its data script. Video decoding depends on the browser's
codec support and the current bundle size limit is 2 MiB.

Share each module with `EYG_ORIGIN=http://localhost:8001 eyg share <path>`.
Reference the returned `#<cid>` to pin the viewer independently from its data.

Tests: `eyg script eyg_packages/artifact_viewers/entry.eyg`, plus the actual
browser interactions in `packages/overlay_public/test/browser/viewers.spec.mjs`.
