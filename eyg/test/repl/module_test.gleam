import gleam/io
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import glance
import scintilla/value.{Closure, F, I, L, R, S, T}
import scintilla/reason as r
import repl/runner
import repl/reader
import plinth/javascript/console
import gleeunit/should

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
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(None, state)) = runner.read(term, initial)

  let line = "foo.Foo(2, \"\")"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(return, _)) = runner.read(term, state)
  return
  |> should.equal(
    Some(
      R("Foo", [glance.Field(Some("a"), I(2)), glance.Field(Some("b"), S(""))]),
    ),
  )

  let line = "foo.Foo(2, b: \"\")"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(return, _)) = runner.read(term, state)
  return
  |> should.equal(
    Some(
      R("Foo", [glance.Field(Some("a"), I(2)), glance.Field(Some("b"), S(""))]),
    ),
  )

  let line = "foo.Foo(2, c: \"\")"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(r.MissingField("c"))

  let line = "foo.Foo(2, \"\", 4)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(r.IncorrectArity(2, 3))

  let line = "foo.Foo(2)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(r.IncorrectArity(2, 1))
}

pub fn module_record_override_test() {
  let mod =
    "
    pub type Foo {
      Foo(a: Int, b: String)
    }"
  let assert Ok(m) = reader.module(mod)

  let modules = dict.from_list([#("lib/foo", m)])
  let initial = runner.init(dict.new(), modules)

  let line = "import lib/foo"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(None, state)) = runner.read(term, initial)

  let line = "let x = foo.Foo(2, \"\")"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(return, state)) = runner.read(term, state)

  let line = "foo.Foo(..x, b: \"h\", a: 4)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(return, _)) = runner.read(term, state)
  return
  |> should.equal(
    Some(
      R("Foo", [glance.Field(Some("a"), I(4)), glance.Field(Some("b"), S("h"))]),
    ),
  )

  let line = "foo.Foo(2, c: \"\")"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Error(reason) = runner.read(term, state)
  reason
  |> should.equal(r.MissingField("c"))
}
// TODO test unlabelled
