//// Triggers run an EYG script when an event in a channel matches a pattern.
////
//// Triggers are installed per channel, by the channel's configuration or by programs
//// with the `AddTrigger` effect. A pattern is a pure EYG function from the event to a boolean.
//// Scripts are functions of the event, or source text with `event` in scope, run with the channel shell.
//// Patterns and function scripts are kept as captured expressions, source scripts as text,
//// see `notes/cloud-process-boundaries.md`.

import cloud/plugins/chat_input
import cloud/plugins/whatsapp
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/capture
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/list
import gleam/result

/// A pure function from event to boolean,
/// captured with only the variables it uses so it can be sent between processes.
pub type Pattern =
  ir.Node(#(Int, Int))

pub type Trigger {
  Trigger(name: String, pattern: Pattern, script: Script, active: Bool)
}

/// What a trigger runs when its pattern matches, with the channel shell.
pub type Script {
  /// A function from the event, captured like a pattern. It may perform effects.
  Function(Pattern)
  /// EYG source with `event` in scope.
  Source(String)
}

/// Tagged chat payloads supplied to configured triggers.
pub fn event_type() {
  t.union(list.append(chat_input.event_types(), whatsapp.event_types()))
}

pub fn type_() {
  t.record([
    #("name", t.String),
    #("pattern", t.Fun(event_type(), t.Empty, t.boolean)),
    #("script", t.Fun(event_type(), t.Var(0), t.Var(1))),
  ])
}

/// Decode a trigger, its pattern must be a function and its script must parse.
pub fn decode(
  value: state.Value(#(Int, Int)),
) -> Result(Trigger, state.Reason(#(Int, Int))) {
  use name <- result.try(cast.field("name", cast.as_string, value))
  use pattern <- result.try(cast.field("pattern", as_function, value))
  use script <- result.try(cast.field("script", as_script, value))
  Ok(Trigger(name:, pattern:, script:, active: True))
}

/// A function, or source text that parses.
fn as_script(value) {
  case value {
    v.String(code) ->
      case parser.all_from_string(code) {
        Ok(_) -> Ok(Source(code))
        Error(_) -> Error(break.IncorrectTerm("a script that parses", value))
      }
    _ ->
      as_function(value)
      |> result.map(Function)
      |> result.replace_error(break.IncorrectTerm(
        "a function or source text",
        value,
      ))
  }
}

fn as_function(value) {
  case value {
    v.Closure(..) | v.Partial(..) -> Ok(capture.capture(value, #(0, 0)))
    _ -> Error(break.IncorrectTerm("a function", value))
  }
}

pub fn describe(trigger: Trigger) -> String {
  case trigger.active {
    True -> trigger.name
    False -> trigger.name <> " (stopped)"
  }
}
