import gleam/io
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import repl/runner.{Closure, F, I, L, R, S, T}
import repl/reader
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
