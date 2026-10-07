//// The module for dealing with tool calls from an LLM
//// There is more than way to wire up an agent to user input.
//// User input is not the responsibility of this module and it handles the inner loop only.

import eyg/analysis/type_/binding/debug
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
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

  "You are an expert automation assistant.
You help users by executing EYG scripts to interact with the users system.
Do not guess language syntax, library functions, effect signatures, or external API contracts.
Consult documentation and probe small examples before building on them.

ALWAYS use djot syntax for your responses.
DO NOT write code blocks in your responses unless explicitly asked.
All code execution uses the 'run' tool.
Every program has the variable context in scope, it is the module described in the Context section at the end of this prompt.
Each run has a fresh local scope, bindings from earlier calls are not retained. 
Returned values and output from StandardOut and StandardError are included in the tool result.
Large tool results are truncated with an explicit marker.
 
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

## Documentation and packages

Full documentation, inclueding an index of guides is available at " <> origin.to_string(
    origin,
  ) <> "/llms.txt.
The index covers libraries, HTTP, JSON, filesystem operations, builtins, and testing.

Published packages are available directly as @name expressions, there is no install step.
Prefer maintained packages to implementing general-purpose utilities locally, especially encoders and parsers for structured formats.
A package is alway pure find the available fields by evaluating simply `@package` and reviewing the tool return.

## Policies and credentials

This environment has the following effects

"
  |> string.append(
    effects
    |> list.map(describe_effect)
    |> string.join("\n"),
  ) <> "

Remember to always use perform to call an effect.

# Context

" <> readme
}

pub fn describe_effect(effect: interface.Interface(a, b)) -> String {
  let interface.Interface(name:, lift_type:, lower_type:, decode: _) = effect
  debug.render_effect(name, lift_type, lower_type)
}

/// Print strings directly, this is needed so fetched documents do not have escapes in the code examples.
pub fn inspect_result(value: v.Value(_, _)) -> String {
  case value {
    v.String(text) -> text
    _ -> simple_debug.inspect(value)
  }
}

/// Bound tool context while retaining both initial content and final diagnostics.
/// The marker makes omission explicit and tells the agent how to recover detail.
pub fn tool_result_text(text: String) -> String {
  let length = string.length(text)
  case length <= 24_000 {
    True -> text
    False ->
      string.slice(text, 0, 12_000)
      <> "\n\n[Tool result truncated: "
      <> int.to_string(length - 24_000)
      <> " characters omitted. Return a focused section or selected fields in another run to inspect the missing content.]\n\n"
      <> string.slice(text, length - 12_000, 12_000)
  }
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
