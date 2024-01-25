import gleam/io
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
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
// TODO read bool module
// pub fn module_test() {
//   let mod =
//     "
//     pub fn foo(a x, b, y) {
//       x - y
//     }"
//   let assert Ok(m) =
//     runner.module(mod)
//     |> io.debug

//   "import lib/foo"
//   |> reader.parse()
//   |> io.debug
//   // |> should.equal(Ok(I(1)))
// }
