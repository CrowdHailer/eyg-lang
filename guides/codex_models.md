---
name: Codex subscription models
description: Configure the Codex Responses compatibility adapter and check credential refresh, tool calls and trajectory replay.
---

# Codex subscription models

This adapter preserves the source branch's private Codex transport at
`chatgpt.com/backend-api/codex/responses`. It uses a ChatGPT access token and
account ID. This endpoint is undocumented and may change; the checked scope is
the protocol fixtures below. For a documented integration in a new app, use
[Sign in with ChatGPT](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt).

The EYG helper reads the Codex **file** credential cache. Codex can also store
credentials in an OS keyring or memory; the helper does not read those stores.
See [Codex authentication](https://developers.openai.com/codex/auth).

In a repository-root configuration:

```eyg
let {codex, policy} = import "./eyg_packages/overlay/index.eyg"
let provider = match codex.read("/absolute/path/to/auth.json") {
  Ok(provider) -> { provider }
  Error(reason) -> {
    let _ = perform StandardError(reason)
    !never(perform Exit(1))
  }
}
{
  llm: {provider, model: "your-enabled-codex-model"},
  policy: policy.read_write(["/absolute/path/to/project"]),
  context: {}
}
```

Run `eyg overlay path/to/.overlay.eyg`. Keep the auth cache outside the policy's
allowed project roots. Only the configuration needs its credentials; the agent
does not need to read that file.

`codex.refresh(path)` performs a refresh explicitly. It saves returned tokens
and an updated UTC timestamp before returning a provider, preserving other JSON
fields and tokens the response omits. Keep Codex idle while changing its shared
cache. A save failure returns an error; use `codex login` to recover a rotated
credential that could not be saved.

The adapter supports text and function tools. It buffers SSE events until a
parsed `response.completed`, using that event's output when present. It reports
failed, incomplete and prematurely closed streams as failures. Image inputs,
encrypted reasoning items and assistant phases are not retained by this
compatibility adapter. Reported usage and request context appear in trajectories.

## Check without credentials

```sh
eyg script entry.eyg
cd packages/overlay_llm
gleam test
gleam test --target javascript --runtime bun
cd ../gleam_cli
TEMP=/tmp/eyg-cli-snapshots gleam test --runtime bun
cd ../overlay_web
gleam test --runtime bun
```

EYG checks use fake file contents and handled network/write effects. They cover
token rotation, preserved fields, UTC dates, malformed input, missing optional
tokens and failure without a write. Provider checks cover request headers,
one-byte UTF-8 chunks, split terminal events and failed/incomplete streams. CLI
checks cover an actual tool result of `42`, usage, archive closure and replay;
web checks cover completion and failure handling. They neither read a real
credential cache nor call a live model.

Build the current host CLI, then run from `packages/tracing`:

```sh
EYG_BIN=/absolute/path/to/eyg gleam run -m tracing/codex_config_check
```

This executes the configuration with the committed fake cache and an empty
prompt, saves `recordings/codex-config.json` and checks redaction and replay.
No model request is made.
