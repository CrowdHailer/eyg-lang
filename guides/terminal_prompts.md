---
name: Editing CLI prompts
description: Edit terminal input, recall earlier lines, and preserve piped input for subsequent EYG effects.
---

# Editing CLI prompts

Start the current [CLI](./install_from_source.md) with `eyg`. Type
`let answer = 43`, press Left then Delete, type `1`, and press Enter.
Enter `answer` to see `41`. Press Up then Enter to repeat that query.
`/t answer` reports `Integer`.

| Key | Action |
| --- | --- |
| Left / Right | move by one grapheme |
| Home / End, Ctrl-A / Ctrl-E | go to the start or end |
| Backspace / Delete | remove the previous or next grapheme |
| Up / Down | browse history and return to the unfinished draft |
| Ctrl-U / Ctrl-K | clear the line or its remaining suffix |
| Enter | submit the line |
| Ctrl-C, Ctrl-D on an empty line | end input |

Combining characters and emoji retain their boundaries while editing. History
lasts for the current invocation and includes EYG `Prompt` calls. An empty line
at the shell prompt exits the shell.

While an Overlay agent is working, Ctrl-C stops the turn after its current
completion chunk or tool call returns. Further tool calls are skipped. The CLI
prints `Stopped, send a message to continue.` and accepts another prompt.
Effects already performed remain; the saved trajectory keeps received model
bytes and the interruption. Ctrl-C at the prompt ends the session.

The CLI suite sends a real SIGINT and checks turn restart. Stream tests verify saved interruption events and skipped tool calls.

Piped input consumes one line per `Prompt`, accepting CRLF and a final line
without a newline. Later bytes remain available to subsequent prompts or
`StandardIn`. EOF and invalid UTF-8 return `Error({})`.

Gleam owns the editor and input decoding; `plinthx` binds native descriptor and
terminal operations. The CLI TUI provides syntax highlighting and structural editing.

`packages/loam` tests the editor, split key sequences and real processes consuming Unicode, EOF and remaining stdin.
