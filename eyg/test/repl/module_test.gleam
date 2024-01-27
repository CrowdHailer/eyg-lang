import gleam/io
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import glance
import repl/runner.{Closure, F, I, L, R, S, T}
import repl/reader
import simplifile
import plinth/javascript/console
import gleeunit/should

fn exec_with(src, env) {
  // let env = dict.from_list(env)
  let parsed = reader.parse(src)
  case parsed {
    Ok(reader.Statements(statements)) -> runner.exec(statements, env)
    Error(reason) -> {
      panic as string.inspect(reason)
    }
  }
}

fn exec(src) {
  exec_with(src, runner.prelude())
}

pub fn stdlib_test() {
  let assert Ok(content) =
    simplifile.read("build/packages/gleam_stdlib/src/gleam/bool.gleam")
  let assert Ok(module) = reader.module(content)
  let modules = dict.from_list([#("gleam/bool", module)])

  let state = runner.init(runner.prelude(), modules)

  let line = "import gleam/bool"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)

  let line = "bool.and(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)
  return
  |> should.equal(Some(R("True", [])))
}

pub fn module_records_test() {
  let mod =
    "
    pub type Foo {
      Foo(a: Int, b: String)
    }"
  let assert Ok(m) = reader.module(mod)

  let modules = dict.from_list([#("lib/foo", m)])
  let initial = runner.init(dict.new(), modules)

  let line = "import lib/foo"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(None, state)) = runner.read(term, initial)

  let line = "foo.Foo(2, \"\")"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, _)) = runner.read(term, state)
  return
  |> should.equal(
    Some(
      R("Foo", [glance.Field(Some("a"), I(2)), glance.Field(Some("b"), S(""))]),
    ),
  )

  let line = "foo.Foo(2, b: \"\")"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, _)) = runner.read(term, state)
  return
  |> should.equal(
    Some(
      R("Foo", [glance.Field(Some("a"), I(2)), glance.Field(Some("b"), S(""))]),
    ),
  )

  let line = "foo.Foo(2, c: \"\")"
  let assert Ok(term) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(runner.MissingField("c"))

  let line = "foo.Foo(2, \"\", 4)"
  let assert Ok(term) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(runner.IncorrectArity(2, 3))

  let line = "foo.Foo(2)"
  let assert Ok(term) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(runner.IncorrectArity(2, 1))
}
// TODO test unlabelled
