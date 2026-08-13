//// Renders IR as source, so that a counterexample can be pasted into the CLI.

import eyg/ir/tree as ir
import gleam/bit_array
import gleam/int
import gleam/string

pub fn source(node) {
  let #(expression, _meta) = node
  case expression {
    ir.Variable(label) -> label
    ir.Lambda(label, body) -> "(" <> label <> ") -> { " <> source(body) <> " }"
    ir.Apply(func, argument) -> source(func) <> "(" <> source(argument) <> ")"
    ir.Let(label, definition, body) ->
      "let " <> label <> " = " <> source(definition) <> " " <> source(body)
    ir.Binary(value) -> "<<" <> bit_array.base16_encode(value) <> ">>"
    ir.Integer(value) -> int.to_string(value)
    ir.String(value) -> "\"" <> value <> "\""
    ir.Tail -> "[]"
    ir.Cons -> "!cons"
    ir.Vacant -> "_"
    ir.Empty -> "{}"
    ir.Extend(label) -> "!extend_" <> label
    ir.Select(label) -> "!select_" <> label
    ir.Overwrite(label) -> "!overwrite_" <> label
    ir.Tag(label) -> label
    ir.Case(label) -> "!match_" <> label
    ir.NoCases -> "!nocases"
    ir.Perform(label) -> "perform " <> label
    ir.Handle(label) -> "handle " <> label
    ir.Builtin(identifier) -> "!" <> identifier
    ir.ContentReference(_)
    | ir.ReleaseReference(..)
    | ir.RelativeReference(_) -> "<reference>"
  }
}

/// The IR as it is written in the test suites, useful for a regression case.
pub fn constructor(node) {
  let #(expression, _meta) = node
  case expression {
    ir.Variable(label) -> "ir.variable(" <> quote(label) <> ")"
    ir.Lambda(label, body) ->
      "ir.lambda(" <> quote(label) <> ", " <> constructor(body) <> ")"
    ir.Apply(func, argument) ->
      "ir.apply(" <> constructor(func) <> ", " <> constructor(argument) <> ")"
    ir.Let(label, definition, body) ->
      "ir.let_("
      <> quote(label)
      <> ", "
      <> constructor(definition)
      <> ", "
      <> constructor(body)
      <> ")"
    ir.Binary(_) -> "ir.binary(<<0, 1>>)"
    ir.Integer(value) -> "ir.integer(" <> int.to_string(value) <> ")"
    ir.String(value) -> "ir.string(" <> quote(value) <> ")"
    ir.Tail -> "ir.tail()"
    ir.Cons -> "ir.cons()"
    ir.Vacant -> "ir.vacant()"
    ir.Empty -> "ir.empty()"
    ir.Extend(label) -> "ir.extend(" <> quote(label) <> ")"
    ir.Select(label) -> "ir.select(" <> quote(label) <> ")"
    ir.Overwrite(label) -> "ir.overwrite(" <> quote(label) <> ")"
    ir.Tag(label) -> "ir.tag(" <> quote(label) <> ")"
    ir.Case(label) -> "ir.case_(" <> quote(label) <> ")"
    ir.NoCases -> "ir.nocases()"
    ir.Perform(label) -> "ir.perform(" <> quote(label) <> ")"
    ir.Handle(label) -> "ir.handle(" <> quote(label) <> ")"
    ir.Builtin(identifier) -> "ir.builtin(" <> quote(identifier) <> ")"
    ir.ContentReference(_)
    | ir.ReleaseReference(..)
    | ir.RelativeReference(_) -> "<reference>"
  }
}

fn quote(content) {
  "\"" <> string.replace(content, "\"", "\\\"") <> "\""
}
