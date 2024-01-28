import gleam/io
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import scintilla/value.{Closure, F, I, L, R, S, T}
import scintilla/reason as r
import scintilla/prelude
import repl/reader
import repl/runner
import gleeunit/should

fn exec_with(src, env) {
  // let env = dict.from_list(env)
  let parsed = reader.parse(src)
  case parsed {
    Ok(#(reader.Statements(statements), [])) ->
      runner.exec(statements, env)
      |> result.map_error(fn(e: #(_, _, _)) { e.0 })
    Error(reason) -> {
      io.debug(reason)
      panic("not parsed")
    }
  }
}

fn exec(src) {
  exec_with(src, dict.new())
}

pub fn discard_pattern_test() {
  let assert Error(r.Finished(env)) =
    "let _ = 1"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.Finished(env)) =
    "let _x = 1"
    |> exec()

  dict.size(env)
  |> should.equal(0)
}

// TODO discard

pub fn int_pattern_test() {
  let assert Error(r.Finished(env)) =
    "let 1 = 1"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.FailedAssignment(_, _)) =
    "let 1 = 2"
    |> exec()

  let assert Error(r.IncorrectTerm("Int", _)) =
    "let 1 = #()"
    |> exec()
}

pub fn float_pattern_test() {
  let assert Error(r.Finished(env)) =
    "let 1.0 = 1.0"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.FailedAssignment(_, _)) =
    "let 1.0 = 2.0"
    |> exec()

  let assert Error(r.IncorrectTerm("Float", _)) =
    "let 1.0 = #()"
    |> exec()
}

pub fn string_pattern_test() {
  let assert Error(r.Finished(env)) =
    "let \"hey\" = \"hey\""
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.FailedAssignment(_, _)) =
    "let \"hey\" = \"hello\""
    |> exec()

  let assert Error(r.IncorrectTerm("String", _)) =
    "let \"hey\" = #()"
    |> exec()
}

pub fn string_concat_pattern_test() {
  let assert Error(r.Finished(env)) =
    "let \"he\" <> _ = \"hey\""
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.Finished(env)) =
    "let \"he\" <> x = \"hey\""
    |> exec()
  dict.size(env)
  |> should.equal(1)

  let assert Error(r.FailedAssignment(_, _)) =
    "let \"!\" <> x = \"hello\""
    |> exec()

  let assert Error(r.IncorrectTerm("String", _)) =
    "let \"he\" <> _ = #()"
    |> exec()
}

pub fn tuple_pattern_test() {
  let assert Error(r.Finished(env)) =
    "let #() = #()"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.Finished(env)) =
    "let #(1, 2) = #(1, 2)"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.FailedAssignment(_, _)) =
    "let #(_) = #()"
    |> exec()

  let assert Error(r.IncorrectTerm("Tuple", _)) =
    "let #() = \"hey\""
    |> exec()
}

pub fn list_pattern_test() {
  let assert Error(r.Finished(env)) =
    "let [] = []"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.Finished(env)) =
    "let [1, 2] = [1, 2]"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(r.FailedAssignment(_, _)) =
    "let [_] = []"
    |> exec()

  let assert Error(r.IncorrectTerm("List", _)) =
    "let [] = \"hey\""
    |> exec()
}

pub fn list_spread_pattern_test() {
  let assert Error(r.Finished(env)) =
    "let [a,..b] = [1]"
    |> exec()

  dict.size(env)
  |> should.equal(2)

  let assert Error(r.Finished(env)) =
    "let [a,..b] = [1, 2]"
    |> exec()

  dict.size(env)
  |> should.equal(2)
}

pub fn enum_match_test() {
  let assert Error(r.Finished(_env)) =
    "let True = True"
    |> exec_with(prelude.scope())

  let assert Error(r.FailedAssignment(_, _)) =
    "let True = False"
    |> exec_with(prelude.scope())

  let assert Error(r.IncorrectTerm("Custom Type", _)) =
    "let True = \"hey\""
    |> exec_with(prelude.scope())
}

pub fn record_match_test() {
  let assert Error(r.Finished(_env)) =
    "let Ok(1) = Ok(1)"
    |> exec_with(prelude.scope())

  let assert Error(r.Finished(env)) =
    "let Ok(x) = Ok(1)"
    |> exec_with(prelude.scope())

  dict.get(env, "x")
  |> should.equal(Ok(I(1)))

  let assert Error(r.IncorrectArity(0, 1)) =
    "let Ok() = Ok(2)"
    |> exec_with(prelude.scope())

  let assert Error(r.FailedAssignment(_, _)) =
    "let Ok(1) = Ok(2)"
    |> exec_with(prelude.scope())

  let assert Error(r.IncorrectTerm("Custom Type", _)) =
    "let Ok(_) = \"hey\""
    |> exec_with(prelude.scope())
}

// TODO named args and spread

pub fn assignment_test() {
  let assert Error(r.Finished(env)) =
    "let [1 as a,..[] as b] = [1]"
    |> exec()
  dict.get(env, "a")
  |> should.equal(Ok(I(1)))
  dict.get(env, "b")
  |> should.equal(Ok(L([])))
}
