//// Token usage reported by model providers.
////
//// Ollama reports `prompt_eval_count` and `eval_count`,
//// OpenAI compatible APIs such as Mistral report a `usage` object.
//// Streamed responses report usage in their final event,
//// each line of a body is checked and the last report wins.

import glasshouse/session.{type Usage, Usage}
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

/// Usage reported in a response body, zero if there is none.
pub fn from_response(body: BitArray) -> Usage {
  case bit_array.to_string(body) {
    Ok(text) ->
      [text, ..string.split(text, "\n")]
      |> list.filter_map(fn(line) {
        let line = string.trim(line)
        let line = case line {
          "data:" <> rest -> string.trim(rest)
          _ -> line
        }
        json.parse(line, decoder())
      })
      |> list.last
      |> fn(found) {
        case found {
          Ok(usage) -> usage
          Error(Nil) -> session.no_usage()
        }
      }
    Error(Nil) -> session.no_usage()
  }
}

fn decoder() {
  decode.one_of(
    {
      use input <- decode.field("prompt_eval_count", decode.int)
      use output <- decode.optional_field("eval_count", 0, decode.int)
      decode.success(Usage(input:, output:))
    },
    [
      decode.field(
        "usage",
        {
          use input <- decode.field("prompt_tokens", decode.int)
          use output <- decode.optional_field(
            "completion_tokens",
            0,
            decode.int,
          )
          decode.success(Usage(input:, output:))
        },
        decode.success,
      ),
    ],
  )
}

/// A rough count for text, about four characters a token.
/// Used by development mocks that have no tokenizer.
pub fn estimate(text: String) -> Int {
  { string.length(text) + 3 } / 4
}
