//// A scripted model served like Ollama's chat API, to demonstrate and test agents without a model.
////
//// The script is a list of rules, the first rule whose `prompt` is part of the latest user message is followed.
//// A rule with a `system` text only applies when the system prompt contains it.
//// Each tool result after the user message moves the rule on a step,
//// a step is either `code` for the `run` tool or a `text` answer.
//// `{{result}}` in an answer is replaced by the latest tool result.
////
//// ```json
//// {"rules": [{"prompt": "notes", "system": "", "steps": [{"code": "..."}, {"text": "The notes say {{result}}"}]}]}
//// ```

import glasshouse/usage
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp

pub type Step {
  Code(String)
  Answer(String)
}

pub type Rule {
  Rule(prompt: String, system: String, steps: List(Step))
}

pub fn decoder() -> decode.Decoder(List(Rule)) {
  let step =
    decode.one_of(
      decode.field("code", decode.string, fn(code) {
        decode.success(Code(code))
      }),
      [
        decode.field("text", decode.string, fn(text) {
          decode.success(Answer(text))
        }),
      ],
    )
  let rule = {
    use prompt <- decode.optional_field("prompt", "", decode.string)
    use system <- decode.optional_field("system", "", decode.string)
    use steps <- decode.field("steps", decode.list(step))
    decode.success(Rule(prompt:, system:, steps:))
  }
  decode.field("rules", decode.list(rule), decode.success)
}

pub fn parse(script: String) -> Result(List(Rule), String) {
  json.parse(script, decoder())
  |> result.replace_error("the model script is not a list of rules")
}

type Message {
  Message(role: String, content: String)
}

type Chat {
  Chat(model: String, messages: List(Message), stream: Bool)
}

fn chat_decoder() {
  let message = {
    use role <- decode.field("role", decode.string)
    use content <- decode.optional_field("content", "", decode.string)
    decode.success(Message(role:, content:))
  }
  use model <- decode.field("model", decode.string)
  use messages <- decode.field("messages", decode.list(message))
  use stream <- decode.optional_field("stream", False, decode.bool)
  decode.success(Chat(model:, messages:, stream:))
}

/// The step the conversation has reached.
pub fn next(
  rules: List(Rule),
  system: String,
  messages: List(#(String, String)),
) {
  let #(latest, results) =
    list.fold(messages, #("", []), fn(acc, message) {
      case message {
        #("user", content) -> #(content, [])
        #("tool", content) -> #(acc.0, [content, ..acc.1])
        _ -> acc
      }
    })
  let rule =
    list.find(rules, fn(rule) {
      contains(latest, rule.prompt) && contains(system, rule.system)
    })
  case rule {
    Ok(rule) ->
      case list.drop(rule.steps, list.length(results)) {
        [Code(code), ..] -> Code(code)
        [Answer(text), ..] -> {
          let result = case results {
            [result, ..] -> result
            [] -> ""
          }
          Answer(string.replace(text, "{{result}}", result))
        }
        [] -> Answer("Done.")
      }
    Error(Nil) ->
      Answer("This scripted model has no rule for \"" <> latest <> "\".")
  }
}

fn contains(text, part) {
  string.contains(string.lowercase(text), string.lowercase(part))
}

/// Reply to an Ollama `/api/chat` request, as a stream of JSON lines if the request asks for one.
pub fn reply(
  rules: List(Rule),
  body: BitArray,
  now: Int,
) -> Result(String, String) {
  use text <- result.try(
    bit_array.to_string(body) |> result.replace_error("the body is not text"),
  )
  use Chat(model:, messages:, stream:) <- result.try(
    json.parse(text, chat_decoder())
    |> result.replace_error("the body is not an Ollama chat request"),
  )
  let system =
    list.filter_map(messages, fn(message) {
      case message.role {
        "system" -> Ok(message.content)
        _ -> Error(Nil)
      }
    })
    |> string.join("\n")
  let step =
    next(
      rules,
      system,
      list.map(messages, fn(message) { #(message.role, message.content) }),
    )
  let #(content, calls, output) = case step {
    Code(code) -> #("", [call(code)], code)
    Answer(text) -> #(text, [], text)
  }
  let created =
    timestamp.from_unix_seconds_and_nanoseconds(
      now / 1000,
      { now % 1000 } * 1_000_000,
    )
    |> timestamp.to_rfc3339(calendar.utc_offset)
  let message = fn(content, calls) {
    json.object([
      #("role", json.string("assistant")),
      #("content", json.string(content)),
      #("tool_calls", json.preprocessed_array(calls)),
    ])
  }
  let counts = [
    #("done_reason", json.string("stop")),
    #("prompt_eval_count", json.int(usage.estimate(text))),
    #("eval_count", json.int(usage.estimate(output))),
  ]
  case stream {
    False ->
      json.object([
        #("model", json.string(model)),
        #("created_at", json.string(created)),
        #("message", message(content, calls)),
        #("done", json.bool(True)),
        ..counts
      ])
      |> json.to_string
    True ->
      [
        json.object([
          #("model", json.string(model)),
          #("created_at", json.string(created)),
          #("message", message(content, calls)),
          #("done", json.bool(False)),
        ]),
        json.object([
          #("model", json.string(model)),
          #("created_at", json.string(created)),
          #("message", message("", [])),
          #("done", json.bool(True)),
          ..counts
        ]),
      ]
      |> list.map(fn(line) { json.to_string(line) <> "\n" })
      |> string.concat
  }
  |> Ok
}

fn call(code) {
  json.object([
    #(
      "function",
      json.object([
        #("name", json.string("run")),
        #("arguments", json.object([#("code", json.string(code))])),
      ]),
    ),
  ])
}
