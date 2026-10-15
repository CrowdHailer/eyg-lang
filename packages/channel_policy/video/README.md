# Policy walkthrough video

Open [the chaptered player](output/watch.html), or play
[`output/walkthrough.mp4`](output/walkthrough.mp4) directly.

The video has synthetic English narration, burned-in captions, and an additional
selectable English subtitle track. The player includes chapter buttons. A
[transcript](output/transcript.md), [SRT captions](output/walkthrough.srt), and
[storyboard](output/contact-sheet.jpg) are included.
The regenerated video also shows native engine proof trees and an allowed
reason for each successful page, PR and inference example. Full captured trees
are available in [`output/proofs.json`](output/proofs.json).

## What it demonstrates

1. Writing the existing EYG relationship policy.
2. Writing Gleam page, submitter and reviewer grants.
3. Signing in with Slack and linking a GitHub identity.
4. Allowed and denied application pages.
5. Creating a real Git commit in a fresh temporary demo repository.
6. A mock PR blocked without a qualified reviewer.
7. An approval from the wrong channel remaining blocked.
8. A Platform member approving the current commit successfully.
9. A new real commit requiring a new approval.
10. Membership removal invalidating the approval after reevaluation.
11. Writing an LLM quota policy and evaluating 49/50 versus 50/50 requests.

The interface is an animated illustration, labeled throughout. Login providers,
Slack membership and GitHub reviews are mocked. The permission outcomes come
from actual Gleam execution using the branch's EYG interpreter. The two commit
hashes shown come from an actual isolated Git repository, not invented labels.
The LLM example evaluates admission; it does not contact a model provider.

The proof panels are rendered from `eyg/interpreter/explain` output captured by
the Gleam scenario, rather than manually constructed explanations. They include
the exact membership/grant joins, and the quota's `used=49`, `limit=50` guard
evidence. The initial PR and its reapproval show separate submitter/reviewer
trees. Host checks such as session expiry and approval of the current commit
are labeled separately from Datalog evidence.

## Reproduce

Prerequisites: Gleam, Bun, Git, Python 3 with Pillow, libespeak-ng for offline
speech synthesis, DejaVu fonts and FFmpeg with libx264/AAC encoding. On a Debian
host the rendering dependencies are provided by `python3-pil`, `libespeak-ng1`,
`espeak-ng-data`, `fonts-dejavu-core` and `ffmpeg`.

From `packages/channel_policy`:

```sh
gleam build --warnings-as-errors
gleam test --runtime bun
bun video/capture.mjs
python3 video/render.py
```

`capture.mjs` creates a new temporary Git repository, writes a small fixture,
inspects and commits it, creates two infrastructure commits, then calls
`channel_policy/video_demo.capture`. That Gleam function asserts the policy
outcomes used in the video. `output/capture.json` records source, decisions,
commit IDs and the actual Git command transcript.

`render.py` renders 1920×1080 H.264 at 24 fps, synthesizes local narration, creates
captions and writes the chaptered player. Use `--ffmpeg /path/to/ffmpeg` if the
encoder is not on PATH. `--preview-only` produces the storyboard and individual
scene previews before encoding. Generated files are in `output/`. The finished
video, player, poster, captions, transcript, chapter metadata, storyboard and
captured scenario/proof data are tracked for sharing. Rendering intermediates
such as raw narration, logs and individual frame previews are ignored.

To share the chaptered player, copy `watch.html`, `walkthrough.mp4`, `poster.jpg`,
`walkthrough.srt`, `transcript.md` and `proofs.json` together. The MP4 also works by itself.
