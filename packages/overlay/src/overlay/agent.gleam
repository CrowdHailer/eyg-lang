//// The module for dealing with tool calls from an LLM
//// There is more than way to wire up an agent to user input.
//// User input is not the responsibility of this module and it handles the inner loop only.

import eyg/analysis/type_/binding/debug
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import oas/generator/utils
import ogre/origin.{type Origin}
import overlay/tools/run
import touch_grass/http
import touch_grass/interface

/// Construct the system prompt for an agent
pub fn system_prompt(
  origin: Origin,
  effects: List(interface.Interface(a, b)),
  readme: String,
) -> String {
  let scheme = http.scheme_to_eyg(origin.scheme)
  let host = v.String(origin.host)
  let port = v.option(origin.port, v.Integer)

  "You are an expery automation assistant.
You help users by executing EYG scripts to interact with the users system.
DO NOT guess any function of effects. Only use what you have seen explained and use guide to learn more about writing EYG code.

ALWAYS use djot syntax for your responses.
DO NOT write code blocks in your responses unless explicitly asked.
All code execution uses the 'run' tool.
Every program has the variable context in scope, it is the module described in the Context section at the end of this prompt.

To fetch a guide run the following script.
ALWAYS fetch the EYG syntax guide before writing scripts

```eyg
let request = {
  method: GET({}),
  scheme: " <> simple_debug.inspect(scheme) <> ",
  host: " <> simple_debug.inspect(host) <> ",
  port: " <> simple_debug.inspect(port) <> ",
  path: \"/guides/eyg-syntax-guide.md\",
  query: None({}),
  headers: [],
  body: !string_to_binary(\"\")
}
match perform Fetch(request) {
  Ok({body}) -> {
    match !string_from_binary(body) {
      Ok(text) -> { text }
      Error(_) -> { \"Not a utf-8 response.\" }
    }
  }
  Error(reason) -> { !string_append(\"fetch guide \", reason) }
}
```

Other guides are
- /guides/builtins-reference.md
- /guides/http-fetch.md

This environment has the following effects

"
  |> string.append(
    effects
    |> list.map(fn(effect) {
      let interface.Interface(name:, lift_type:, lower_type:, decode: _) =
        effect

      "-"
      <> name
      <> "("
      <> debug.mono(lift_type)
      <> "_ -> "
      <> debug.mono(lower_type)
    })
    |> string.join("\n"),
  ) <> "

Remember to always use perform to call an effect.

Use the service effects, such as DNSimple, to call service API's these do not require the scheme, host or port to be set.
They do not require an API token this will be added by the platform.

# Context

" <> readme
}

pub type ToolCall {
  Run(String)
}

pub type CastFailure {
  DecodeError(errors: List(decode.DecodeError))
  UnknownTool
}

pub fn describe_failure(
  failure: CastFailure,
  name: String,
  arguments: Dict(String, utils.Any),
) -> String {
  case failure {
    DecodeError(errors: _) -> {
      "Bad arguments for tool "
      <> name
      <> " arguments: "
      <> json.to_string(utils.any_to_json(utils.Object(arguments)))
    }
    UnknownTool -> {
      let message = "Failed to call tool `" <> name <> "` it is not setup."
      message
    }
  }
}

pub fn cast_tool_call(
  name: String,
  arguments: Dict(String, utils.Any),
) -> Result(ToolCall, CastFailure) {
  case name {
    "run" -> run.cast(arguments) |> to(Run)
    _ -> Error(UnknownTool)
  }
}

fn to(result, call) {
  case result {
    Ok(arguments) -> Ok(call(arguments))
    Error(reason) -> Error(DecodeError(reason))
  }
}
