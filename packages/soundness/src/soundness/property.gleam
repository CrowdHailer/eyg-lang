//// The soundness property.
////
//// If the analysis accepts a program in a pure context then running it must
//// not fail. Every failure of eval is a type error, there is no other kind,
//// so a program that checks and then fails is a hole in the type system.
//// Non termination is the one legitimate outcome that is not a value, so
//// evaluation is given a fixed amount of fuel.
////
//// The value that comes back is checked against the type the analysis
//// inferred as well. A program that returns a String where the analysis
//// promised an Integer has not failed yet, but it will as soon as it is used
//// in a larger program.

import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import soundness/print

pub type Outcome {
  /// The analysis rejected the program, it says nothing about soundness.
  Rejected(reason: String)
  /// The program ran out of fuel, it says nothing about soundness.
  Exhausted
  /// The analysis accepted the program and it ran to a value of that type.
  Sound
  /// The analysis accepted the program and running it failed.
  Failed(reason: String, type_: t.Type(Int))
  /// The analysis accepted the program and it ran to a value of another type.
  Mismatched(value: String, type_: t.Type(Int))
}

pub fn check(source, fuel) {
  let analysis = j.check(j.pure(), source)
  case j.all_errors(analysis) {
    [#(_meta, reason), ..] -> Rejected(string.inspect(reason))
    [] -> {
      let type_ = j.type_(analysis)
      case evaluate(source, fuel) {
        Error(option.None) -> Exhausted
        Error(option.Some(reason)) -> Failed(reason, type_)
        Ok(value) ->
          case conforms(value, type_) {
            True -> Sound
            False -> Mismatched(inspect(value), type_)
          }
      }
    }
  }
}

/// Run a program, returning Error(None) if it does not finish in time.
pub fn evaluate(source, fuel) {
  do_run(state.step(state.E(source), builtin.default([]), state.Empty), fuel)
}

fn do_run(next, fuel) {
  case fuel <= 0 {
    True -> Error(option.None)
    False ->
      case next {
        state.Loop(c, e, k) -> do_run(state.step(c, e, k), fuel - 1)
        state.Break(Ok(value)) -> Ok(value)
        state.Break(Error(#(reason, _meta, _env, _stack))) ->
          Error(option.Some(describe(reason)))
      }
  }
}

fn describe(reason) {
  case reason {
    break.NotAFunction(value) -> "not a function: " <> inspect(value)
    break.UndefinedVariable(label) -> "undefined variable: " <> label
    break.UndefinedBuiltin(label) -> "undefined builtin: " <> label
    break.UndefinedReference(_) -> "undefined reference"
    break.UndefinedRelease(..) -> "undefined release"
    break.UndefinedRelative(location:) -> "undefined relative: " <> location
    break.Vacant -> "vacant"
    break.NoMatch(term:) -> "no match: " <> inspect(term)
    break.UnhandledEffect(label, _) -> "unhandled effect: " <> label
    break.IncorrectTerm(expected:, got:) ->
      "expected " <> expected <> " got " <> inspect(got)
    break.MissingField(label) -> "missing field: " <> label
    break.Unrepresentable(builtin:, args: _) -> "unrepresentable: " <> builtin
  }
}

pub fn inspect(value) {
  case value {
    v.Binary(_) -> "Binary"
    v.Integer(_) -> "Integer"
    v.String(_) -> "String"
    v.LinkedList(_) -> "List"
    v.Record(fields) -> "Record(" <> string.join(dict.keys(fields), ", ") <> ")"
    v.Tagged(label, _) -> "Tagged(" <> label <> ")"
    v.Closure(..) -> "Function"
    v.Partial(_, _) -> "Function"
  }
}

/// Does a value have the shape the type promises?
///
/// Only the parts of a type that are visible in a value are checked. Nothing
/// can be said about the body of a function without applying it, and an open
/// row says the value may carry fields or tags the type does not name.
pub fn conforms(value, type_) {
  case type_, value {
    t.Var(_), _ -> True
    t.Integer, v.Integer(_) -> True
    t.String, v.String(_) -> True
    t.Binary, v.Binary(_) -> True
    t.List(element), v.LinkedList(elements) ->
      list.all(elements, conforms(_, element))
    t.Record(rows), v.Record(fields) -> record_conforms(rows, fields)
    t.Union(rows), v.Tagged(label, inner) -> union_conforms(rows, label, inner)
    t.Fun(_, _, _), v.Closure(..) -> True
    t.Fun(_, _, _), v.Partial(_, _) -> True
    t.Promise(_), _ -> True
    _, _ -> False
  }
}

fn record_conforms(rows, fields) {
  case rows {
    t.Empty -> True
    t.Var(_) -> True
    t.RowExtend(label, expected, tail) ->
      case dict.get(fields, label) {
        Ok(value) ->
          conforms(value, expected)
          && record_conforms(tail, dict.delete(fields, label))
        Error(Nil) -> False
      }
    _ -> False
  }
}

fn union_conforms(rows, label, value) {
  case rows {
    // An open row can always be extended with the tag that is there.
    t.Var(_) -> True
    t.RowExtend(l, expected, tail) ->
      case l == label {
        True -> conforms(value, expected)
        False -> union_conforms(tail, label, value)
      }
    _ -> False
  }
}

/// A report for a failing program, in a form that can be pasted somewhere
/// useful.
pub fn report(source, outcome) {
  case outcome {
    Failed(reason:, type_:) ->
      "checks as "
      <> render(type_)
      <> " and then fails with "
      <> reason
      <> "\n  "
      <> print.source(source)
      <> "\n  "
      <> print.constructor(source)
    Mismatched(value:, type_:) ->
      "checks as "
      <> render(type_)
      <> " and evaluates to "
      <> value
      <> "\n  "
      <> print.source(source)
      <> "\n  "
      <> print.constructor(source)
    _ -> "sound"
  }
}

fn render(type_) {
  debug.mono(type_)
}
