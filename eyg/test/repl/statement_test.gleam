import gleam/dict
import gleam/io
import gleam/option.{None, Some}
import simplifile
import glance as g
import scintilla/value.{I, R}
import repl/reader
import repl/runner
import gleeunit/should

const bool_mod = "build/packages/gleam_stdlib/src/gleam/bool.gleam"

pub fn import_module_test() {
  let assert Ok(content) = simplifile.read(bool_mod)
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

pub fn import_aliased_module_test() {
  let assert Ok(content) = simplifile.read(bool_mod)
  let assert Ok(module) = reader.module(content)
  let modules = dict.from_list([#("gleam/bool", module)])

  let state = runner.init(runner.prelude(), modules)

  let line = "import gleam/bool as b"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)

  let line = "b.and(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)
  return
  |> should.equal(Some(R("True", [])))

  let line = "bool.and(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(runner.UndefinedVariable("bool"))
}

pub fn import_unqualified_module_test() {
  let assert Ok(content) = simplifile.read(bool_mod)
  let assert Ok(module) = reader.module(content)
  let modules = dict.from_list([#("gleam/bool", module)])

  let state = runner.init(runner.prelude(), modules)

  let line = "import gleam/bool.{and as alltogether, or}"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)

  let line = "alltogether(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)
  return
  |> should.equal(Some(R("True", [])))

  let line = "and(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(runner.UndefinedVariable("and"))

  let line = "or(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)
  return
  |> should.equal(Some(R("True", [])))

  let line = "bool.negate(True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)
  return
  |> should.equal(Some(R("False", [])))
}

pub fn custom_enum_test() {
  let state = runner.init(dict.new(), dict.new())
  let assert Ok(term) =
    reader.parse(
      "type Foo {
    A
    B
  }",
    )
  let assert Ok(#(return, state)) = runner.read(term, state)

  let assert Ok(term) = reader.parse("A")
  let assert Ok(#(return, _)) = runner.read(term, state)

  return
  |> should.equal(Some(R("A", [])))
}

pub fn custom_record_test() {
  let state = runner.init(dict.new(), dict.new())
  let assert Ok(term) =
    reader.parse(
      "type Wrap {
    Wrap(Int)
  }",
    )
  let assert Ok(#(return, state)) = runner.read(term, state)

  let assert Ok(term) = reader.parse("Wrap(2)")
  let assert Ok(#(return, _)) = runner.read(term, state)

  return
  |> should.equal(Some(R("Wrap", [g.Field(None, I(2))])))
}
