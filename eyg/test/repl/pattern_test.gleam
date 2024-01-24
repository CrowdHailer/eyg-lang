import gleam/io
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import glance
import glexer
import repl/runner.{Closure, F, I, L, R, S, T}
import gleeunit/should

fn exec_with(src, env) {
  // let env = dict.from_list(env)
  let parsed =
    glexer.new(src)
    |> glexer.lex
    |> list.filter(fn(pair) { !glance.is_whitespace(pair.0) })
    |> runner.statements([], _)
  case parsed {
    Ok(#(statements, _, rest)) -> runner.exec(statements, env)
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
  let assert Error(runner.Finished(env)) =
    "let _ = 1"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.Finished(env)) =
    "let _x = 1"
    |> exec()

  dict.size(env)
  |> should.equal(0)
}

// TODO discard

pub fn int_pattern_test() {
  let assert Error(runner.Finished(env)) =
    "let 1 = 1"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.FailedAssignment(_, _)) =
    "let 1 = 2"
    |> exec()

  let assert Error(runner.IncorrectTerm("Int", _)) =
    "let 1 = #()"
    |> exec()
}

pub fn float_pattern_test() {
  let assert Error(runner.Finished(env)) =
    "let 1.0 = 1.0"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.FailedAssignment(_, _)) =
    "let 1.0 = 2.0"
    |> exec()

  let assert Error(runner.IncorrectTerm("Float", _)) =
    "let 1.0 = #()"
    |> exec()
}

pub fn string_pattern_test() {
  let assert Error(runner.Finished(env)) =
    "let \"hey\" = \"hey\""
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.FailedAssignment(_, _)) =
    "let \"hey\" = \"hello\""
    |> exec()

  let assert Error(runner.IncorrectTerm("String", _)) =
    "let \"hey\" = #()"
    |> exec()
}

pub fn string_concat_pattern_test() {
  let assert Error(runner.Finished(env)) =
    "let \"he\" <> _ = \"hey\""
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.Finished(env)) =
    "let \"he\" <> x = \"hey\""
    |> exec()
  dict.size(env)
  |> should.equal(1)

  let assert Error(runner.FailedAssignment(_, _)) =
    "let \"!\" <> x = \"hello\""
    |> exec()

  let assert Error(runner.IncorrectTerm("String", _)) =
    "let \"he\" <> _ = #()"
    |> exec()
}

pub fn tuple_pattern_test() {
  let assert Error(runner.Finished(env)) =
    "let #() = #()"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.Finished(env)) =
    "let #(1, 2) = #(1, 2)"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.FailedAssignment(_, _)) =
    "let #(_) = #()"
    |> exec()

  let assert Error(runner.IncorrectTerm("Tuple", _)) =
    "let #() = \"hey\""
    |> exec()
}

pub fn list_pattern_test() {
  let assert Error(runner.Finished(env)) =
    "let [] = []"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.Finished(env)) =
    "let [1, 2] = [1, 2]"
    |> exec()

  dict.size(env)
  |> should.equal(0)

  let assert Error(runner.FailedAssignment(_, _)) =
    "let [_] = []"
    |> exec()

  let assert Error(runner.IncorrectTerm("List", _)) =
    "let [] = \"hey\""
    |> exec()
}

pub fn list_spread_pattern_test() {
  let assert Error(runner.Finished(env)) =
    "let [a,..b] = [1]"
    |> exec()

  dict.size(env)
  |> should.equal(2)

  let assert Error(runner.Finished(env)) =
    "let [a,..b] = [1, 2]"
    |> exec()

  dict.size(env)
  |> should.equal(2)
}

pub fn enum_match_test() {
  let assert Error(runner.Finished(_env)) =
    "let True = True"
    |> exec_with(runner.prelude())

  let assert Error(runner.FailedAssignment(_, _)) =
    "let True = False"
    |> exec_with(runner.prelude())

  let assert Error(runner.IncorrectTerm("Custom Type", _)) =
    "let True = \"hey\""
    |> exec_with(runner.prelude())
}

pub fn record_match_test() {
  let assert Error(runner.Finished(_env)) =
    "let Ok(1) = Ok(1)"
    |> exec_with(runner.prelude())

  let assert Error(runner.Finished(env)) =
    "let Ok(x) = Ok(1)"
    |> exec_with(runner.prelude())

  dict.get(env, "x")
  |> should.equal(Ok(I(1)))

  let assert Error(runner.IncorrectArity(0, 1)) =
    "let Ok() = Ok(2)"
    |> exec_with(runner.prelude())

  let assert Error(runner.FailedAssignment(_, _)) =
    "let Ok(1) = Ok(2)"
    |> exec_with(runner.prelude())

  let assert Error(runner.IncorrectTerm("Custom Type", _)) =
    "let Ok(_) = \"hey\""
    |> exec_with(runner.prelude())
}

// TODO named args and spread

pub fn assignment_test() {
  let assert Error(runner.Finished(env)) =
    "let [1 as a,..[] as b] = [1]"
    |> exec()
  dict.get(env, "a")
  |> should.equal(Ok(I(1)))
  dict.get(env, "b")
  |> should.equal(Ok(L([])))
}
