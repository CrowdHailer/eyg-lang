---
name: Evaluate model-written EYG
description: Ask a model for a pure EYG program, check its type and grade the computed value.
---

# Evaluate model-written EYG

From `packages/overlay_eval`:

```sh
gleam test
gleam run -m overlay/eval/pure -- ollama-local:your-tool-model
```

For an OpenAI-compatible local endpoint:

```sh
OVERLAY_EVAL_OPENAI_ORIGIN=http://127.0.0.1:7210 \
  gleam run -m overlay/eval/pure -- openai-local:your-tool-model
```

Ollama Cloud uses `ollama:<model>` and `OLLAMA_API_KEY`. The local modes use no
API key. Choose a model with function-tool support. An optional second argument
sets the repository root; its default is `../..`.

The task asks for the sum of the first 20 Fibonacci numbers starting with
`1, 1`. The expected result `17710` stays in the grader. The model receives the
shared Overlay instructions, the syntax and builtin guides, and the `run` tool.
It must submit exactly one call with a string `code` argument. Prose is not graded.

The evaluator checks the program before running it. No external effects or
imports are available; `context` is `{}`. Execution uses the interpreter's finite
reduction budget, and the network response has a 300-second deadline.

It prints the submitted source followed by `PASS` or `FAIL`. A wrong value,
type/syntax error, missing tool call or provider error exits nonzero. One attempt
measures that attempt; it does not estimate a model's reliability.

The offline checks cover Fibonacci calculation, wrong values, rejected effects
and references, malformed tool arguments, missing tool calls, divergence and
deadlines. They also check that the request does not contain the answer.
