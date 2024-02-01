import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import glexer
import glance
import simplifile
import scintilla/value as v
import scintilla/reason as r
import scintilla/repl
import scintilla/prelude
import gleeunit/should

fn declare(src, state) {
  src
  glexer.new(src)
  |> glexer.lex
  |> list.filter(fn(pair) { !glance.is_whitespace(pair.0) })
  |> glance.declaration()
  |> should.be_ok
  |> fn(t: #(_, _)) { t.0 }()
  |> repl.declare(state)
}

fn exec(src, state) {
  src
  |> glance.statements()
  |> should.be_ok()
  |> repl.exec(state)
}

fn standard() {
  let content =
    simplifile.read(bool_mod)
    |> should.be_ok
  let module =
    glance.module(content)
    |> should.be_ok

  let modules = dict.from_list([#("gleam/bool", module)])
  let state = #(prelude.scope(), modules)
}

pub fn attribute_test() {
  "@external(javascript)"
  |> declare(repl.empty(dict.new()))
  |> should.equal(Error(r.Unsupported("attributes")))
}

const bool_mod = "build/packages/gleam_stdlib/src/gleam/bool.gleam"

pub fn import_module_test() {
  let state =
    "import gleam/bool"
    |> declare(standard())
    |> should.be_ok()

  let #(value, _state) =
    "bool.and(True, True)"
    |> exec(state)
    |> should.be_ok

  value
  |> should.equal(v.R("True", []))
}
// pub fn import_aliased_module_test() {
//   let assert Ok(content) = simplifile.read(bool_mod)
//   let assert Ok(module) = reader.module(content)
//   let modules = dict.from_list([#("gleam/bool", module)])

//   let state = runner.init(prelude.scope(), modules)

//   let line = "import gleam/bool as b"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(None, state)) = runner.read(term, state)

//   let line = "b.and(True, True)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(return, state)) = runner.read(term, state)
//   return
//   |> should.equal(Some(v.R("True", [])))

//   let line = "bool.and(True, True)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Error(reason) = runner.read(term, state)
//   reason
//   |> should.equal(r.UndefinedVariable("bool"))
// }

// pub fn import_unqualified_module_test() {
//   let assert Ok(content) = simplifile.read(bool_mod)
//   let assert Ok(module) = reader.module(content)
//   let modules = dict.from_list([#("gleam/bool", module)])

//   let state = runner.init(prelude.scope(), modules)

//   let line = "import gleam/bool.{and as alltogether, or}"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(None, state)) = runner.read(term, state)

//   let line = "alltogether(True, True)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(return, state)) = runner.read(term, state)
//   return
//   |> should.equal(Some(v.R("True", [])))

//   let line = "and(True, True)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Error(reason) = runner.read(term, state)
//   reason
//   |> should.equal(r.UndefinedVariable("and"))

//   let line = "or(True, True)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(return, state)) = runner.read(term, state)
//   return
//   |> should.equal(Some(v.R("True", [])))

//   let line = "bool.negate(True)"
//   let assert Ok(#(term, [])) = reader.parse(line)
//   let assert Ok(#(return, _state)) = runner.read(term, state)
//   return
//   |> should.equal(Some(v.R("False", [])))
// }
