# Artifact workspace demo

This is a real Ollama agent recording, using the browser application's `run`
tool, the local hub, and live public HTTP APIs. The recording script does not
inject tool results, artifacts, or mock API responses.

## Shared modules

These modules were shared to `http://localhost:8001`:

| Module | Content ID |
| --- | --- |
| Dwindle | `baguqeeral2ejqm237cccbfzgwznch7kyuovu5m2qmwfcls5lfm5ujbga5bia` |
| Main and stack | `baguqeera4kw7qff5y35g7bilhu4jr7z3vll6f3a36vjyum6mm5zziilimllq` |
| Carousel | `baguqeera5ao55wllogfmehwtk4lsid3qlgesn3jswyxlk3vtccspd3omjfwa` |
| Video player | `baguqeera5ezsincotf343ldn6srr2h2fpgtomd2ds4bxvzu3fov7s3jhzala` |
| Bluesky posts | `baguqeerarfxbll53dm5ory3zjkr7e237qw377leg4njmxcpsxcwlzzn4rgpq` |
| Demo context | `baguqeera5huasaub27uqjbwbdqqf3ulww6nsljgfc65uxiqhsfkysm7zxaxq` |

`demo/context.eyg` imports the five modules; sharing it recursively shares its
dependencies. It also provides generic HTTPS text/binary helpers around the
existing Fetch effect and a string-concatenation helper, so the demo agent can
concentrate on the generated application. These helpers are tested with
`eyg script packages/overlay_public/demo/test.eyg`.
To populate a fresh local hub, run from the repository root:

```sh
EYG_ORIGIN=http://localhost:8001 eyg share packages/overlay_public/demo/context.eyg
```

The returned CID should match the table for this source revision. Open
`http://127.0.0.1:5173/overlay/?reference=<cid>`.

## Record

In `packages/overlay_public`, install dependencies and the matching browser:

```sh
bun install
bun x playwright install chromium ffmpeg
EYG_HUB=http://localhost:8001 bun --bun run dev -- --host 127.0.0.1
```

In another terminal, supply `OLLAMA_API_KEY` through your environment, then:

```sh
bun demo/record.mjs
```

Optional environment variables: `OVERLAY_URL`, `ARTIFACT_CONTEXT`, `OLLAMA_MODEL`, `RECORDING_DIR`.
The default model is `qwen3.5:397b`. The key goes directly into browser session
storage, never into a source file, chat prompt, transcript, or visible form.
Recording output is ignored by Git:

- `recordings/artifacts-demo.webm`: full recording, including model wait time.
- `recordings/workspace.png`: five tiled artifact applications.
- `recordings/history.png`: artifact history/diff demonstration.
- `recordings/agent-transcript.json`: model responses and public-data request
  status/timestamps (no HTTP request headers or credentials).

The recorder checks that displayed arrival minutes agree with the API's seconds
and closes unrelated panels before the revision demonstration. Failed takes
are saved as `artifacts-incomplete.webm`, rather than replacing a successful
recording.

## Thinking at 10×

`recordings/artifacts-demo-thinking-10x.mp4` is the edited recording: 2m 31s,
with the 22 thinking intervals at 10× and all other footage at normal speed.
The original 5m 37s WebM is preserved.

Recreate this edit with a full FFmpeg installation (including `libx264`):

```sh
python3 demo/speed-up-thinking.py
```

Set `FFMPEG` to an explicit executable if needed. The editor aligns the saved
Ollama chunk timestamps with the recording's creation time, accounting for each
response's browser receipt time. A thinking interval ends when visible answer
text or a tool call appears. Timing is limited to that of the original stream
log. `--plan-only` emits the edit timeline without encoding. The timeline is
saved in `recordings/thinking-10x-timeline.json`; the editor also verifies the
output duration and decodes the complete output to check for media errors.

## Sources and interpretation

- TfL stop `490008660N` (Lady Somerset Road): live stop metadata and arrivals.
- Reading Buses `reading-buses.co.uk`: latest public Bluesky posts, explicitly
  a separate operator from the London stop. This account had posts when checked;
  the TfL and Lothian accounts checked had empty feeds.
- MDN `media/cc0-videos/flower.webm`: a short CC0 sample for video controls,
  labelled as a sample rather than bus footage.
- Map and carousel illustrations: original SVG created by the agent, with the
  map labelled schematic rather than claiming accurate street geometry.

Network is available to the agent's `Fetch` effect, not the embedded viewers.
The viewer functions decide how to interpret their input data. The platform
only stores versioned bundles and displays isolated HTML.
