import gleam/dict
import gleam/option.{None, Some}
import simplifile
import glance as g
import scintilla/value as v
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
  let assert Ok(#(None, state)) = runner.read(term, state)

  let line = "bool.and(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, _state)) = runner.read(term, state)
  return
  |> should.equal(Some(v.R("True", [])))
}

pub fn import_aliased_module_test() {
  let assert Ok(content) = simplifile.read(bool_mod)
  let assert Ok(module) = reader.module(content)
  let modules = dict.from_list([#("gleam/bool", module)])

  let state = runner.init(runner.prelude(), modules)

  let line = "import gleam/bool as b"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(None, state)) = runner.read(term, state)

  let line = "b.and(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)
  return
  |> should.equal(Some(v.R("True", [])))

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
  let assert Ok(#(None, state)) = runner.read(term, state)

  let line = "alltogether(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)
  return
  |> should.equal(Some(v.R("True", [])))

  let line = "and(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(runner.UndefinedVariable("and"))

  let line = "or(True, True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)
  return
  |> should.equal(Some(v.R("True", [])))

  let line = "bool.negate(True)"
  let assert Ok(term) = reader.parse(line)
  let assert Ok(#(return, _state)) = runner.read(term, state)
  return
  |> should.equal(Some(v.R("False", [])))
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
  let assert Ok(#(None, state)) = runner.read(term, state)

  let assert Ok(term) = reader.parse("A")
  let assert Ok(#(return, _)) = runner.read(term, state)

  return
  |> should.equal(Some(v.R("A", [])))
}

pub fn custom_record_test() {
  let state = runner.init(dict.new(), dict.new())
  let assert Ok(term) =
    reader.parse(
      "type Wrap {
    Wrap(Int)
  }",
    )
  let assert Ok(#(None, state)) = runner.read(term, state)

  let assert Ok(term) = reader.parse("Wrap(2)")
  let assert Ok(#(return, _)) = runner.read(term, state)

  return
  |> should.equal(Some(v.R("Wrap", [g.Field(None, v.I(2))])))
}

pub fn named_record_fields_test() {
  let initial = runner.init(dict.new(), dict.new())
  let assert Ok(term) =
    reader.parse(
      "type Rec {
    Rec(a: Int, b: Float)
  }",
    )
  let assert Ok(#(None, initial)) = runner.read(term, initial)

  let assert Ok(term) = reader.parse("Rec(b: 2.0, a: 1)")
  let assert Ok(#(return, _)) = runner.read(term, initial)
  return
  |> should.equal(
    Some(v.R("Rec", [g.Field(Some("a"), v.I(1)), g.Field(Some("b"), v.F(2.0))])),
  )

  let assert Ok(term) = reader.parse("let x = Rec(b: 2.0, a: 1) x.a")
  let assert Ok(#(return, _)) = runner.read(term, initial)
  return
  |> should.equal(Some(v.I(1)))

  let assert Ok(term) = reader.parse("let x = Rec(b: 2.0, a: 1) x.c")
  let assert Error(reason) = runner.read(term, initial)
  reason
  |> should.equal(runner.MissingField("c"))

  let assert Ok(term) = reader.parse("\"\".c")
  let assert Error(reason) = runner.read(term, initial)
  reason
  |> should.equal(runner.IncorrectTerm("Record", v.S("")))
}

pub fn constant_test() {
  let initial = runner.init(dict.new(), dict.new())
  let assert Ok(term) = reader.parse("pub const x = 5")
  let assert Ok(#(_, initial)) = runner.read(term, initial)

  let assert Ok(term) = reader.parse("x")
  let assert Ok(#(return, _)) = runner.read(term, initial)
  return
  |> should.equal(Some(v.I(5)))
}

pub fn recursive_function_test() {
  let initial = runner.init(dict.new(), dict.new())
  let assert Ok(term) =
    reader.parse(
      "pub fn count(items, total) {
        case items {
          [] -> total
          [_, ..items] -> count(items, total + 1)
        }
      }",
    )
  let assert Ok(#(_, initial)) = runner.read(term, initial)

  let assert Ok(term) = reader.parse("count([], 0)")
  let assert Ok(#(return, _)) = runner.read(term, initial)
  return
  |> should.equal(Some(v.I(0)))

  let assert Ok(term) = reader.parse("count([10, 20], 0)")
  let assert Ok(#(return, _)) = runner.read(term, initial)
  return
  |> should.equal(Some(v.I(2)))
}
