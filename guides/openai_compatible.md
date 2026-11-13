---
name: OpenAI compatible Overlay models
description: Configure a Chat Completions endpoint and check fragmented tool calls, recorded usage and offline replay.
---

# OpenAI compatible Overlay models

Set the `llm` field of an [Overlay configuration](../packages/overlay/README.md):

```eyg
{
  provider: OpenAI({
    origin: "http://localhost:7209",
    api_key: None({}),
    path: "/v1/chat/completions",
    headers: []
  }),
  model: "your-chat-model"
}
```

`origin` selects the server, `path` selects its endpoint, and `headers` accepts
`{key, value}` records. `Some(key)` adds bearer authentication. Supply the rest
of the configuration's policy and context as usual. The adapter supports text
messages and function tools; it does not forward image attachments.

Choose a model with Chat Completions function-tool support. Current OpenAI
documentation requires the Responses API for GPT-6 Astra and GPT-6.1 Sol tool
calling. This adapter implements the Chat Completions contract. [Official
function-calling documentation](https://developers.openai.com/api/docs/guides/function-calling).

Streaming buffers events until `[DONE]`, then joins tool arguments by their
indices before Overlay checks and runs EYG. Split UTF-8 and CRLF event lines
are supported. Requests ask for token usage, which the service reports in its
final usage event; interruption can precede that event. [Official streaming
schema](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).

## Check without an account

Build the current host CLI, then run from `packages/tracing`:

```sh
EYG_BIN=/absolute/path/to/eyg gleam run -m tracing/openai_check
```

The local HTTP fixture checks authentication, extra headers, fragmented
arguments, the actual `!int_add(20, 22)` tool result, two model requests and
reported usage. It saves `recordings/openai-protocol.json` and checks closure
and offline replay. No remote model is called. Provider and configuration
checks also run on the BEAM and JavaScript targets.
