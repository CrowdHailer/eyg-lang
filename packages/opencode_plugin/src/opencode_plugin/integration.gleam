//// Minimal native glue for the pinned OpenCode dispatcher. Policies, mapping,
//// modes, configuration and session ownership are implemented in Gleam.

import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import sha256

pub const version = "1.19.0"

pub const source_sha256 =
  "5ad3f44682fc8e2bacb2222157943de8ab7dd663a1e0ddf5e4a213539b1f67d7"

fn changes() {
  [
    #(
      "import { Agent } from \"@/agent/agent\"",
      "import * as Eyg from \"@/tool/eyg/dispatch.mjs\"\nimport { Agent } from \"@/agent/agent\"",
      1,
    ),
    #(
      "  const flags = yield* RuntimeFlags.Service",
      "  const flags = yield* RuntimeFlags.Service\n  const sessions = yield* Session.Service\n  const eygTools = () => Effect.promise(() => Eyg.wrap_tools(tools, input, (id: string) => run.promise(sessions.get(id as any))))",
      1,
    ),
    #(
      "    metadata: (val) =>\n      input.processor.updateToolCall",
      "    metadata: (val) =>\n      (Eyg.notify(options, val), input.processor.updateToolCall",
      1,
    ),
    #("      }),\n    ask: (req)", "      })),\n    ask: (req)", 1),
    #(
      "            input: args,",
      "            input: Eyg.outer_args(options, args),",
      1,
    ),
    #("return tools", "return yield* eygTools()", 2),
  ]
}

pub fn digest(code) {
  <<code:utf8>> |> sha256.hash |> bit_array.base16_encode |> string.lowercase
}

fn original(code) {
  case digest(code) == source_sha256 {
    True -> Ok(code)
    False -> {
      let restored =
        list.fold(list.reverse(changes()), code, fn(code, change) {
          string.replace(code, change.1, change.0)
        })
      case digest(restored) == source_sha256 {
        True -> Ok(restored)
        False ->
          Error(
            "Expected the unmodified or previously integrated OpenCode v"
            <> version
            <> " dispatcher (SHA-256 "
            <> source_sha256
            <> ")",
          )
      }
    }
  }
}

/// Idempotent and fails closed on other versions or unrelated source changes.
pub fn patch(code) {
  use code <- result.try(original(code))
  list.try_fold(changes(), code, fn(code, change) {
    let #(before, after, count) = change
    case list.length(string.split(code, before)) == count + 1 {
      False -> Error("OpenCode integration anchor did not match")
      True -> Ok(string.replace(code, before, after))
    }
  })
}
