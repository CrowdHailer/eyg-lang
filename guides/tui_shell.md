---
name: TUI shell
description: Use the structural terminal editor and recorded Overlay sessions on their supported runtimes.
---

# TUI shell

`eyg tui` runs the structural editor shared with the web editor. Paste an EYG expression, press Enter to evaluate it, and inspect its value and effects in the history. Arrow keys move through the structure; Space opens the available edits and completions. Escape cancels the current operation. Ctrl-Q exits. `eyg tui file.eyg` loads a shell configuration first.

`StandardIn` and `Prompt` use input widgets owned by the screen. Submitting records the reply with the effect; Escape returns an error to the program. Native terminal input does not compete with program input.

`eyg tui overlay agent.eyg` runs a recorded Overlay session. Type a message and press Enter. Assistant text streams into the transcript; tools execute in order and their policy decisions are retained. Ctrl-O expands code, results and effect details. Ctrl-C stops the active turn, or exits when idle. Each completed or stopped turn saves a trajectory that the CLI can inspect and replay. See [trajectories](./trajectories.md).

From `packages/eyg_tui`, `gleam run` runs the same structural editor, state and renderer on the BEAM. A file argument loads a local configuration. Files, environment, clock, random values and hashes are available. Network requests and writes return errors; unsupported operations stop that evaluation. Overlay requires the JavaScript CLI. This host does not persist the hub cache.
