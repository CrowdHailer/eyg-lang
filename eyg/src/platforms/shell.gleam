import gleam/io
import gleam/option.{None, Some}
import gleam/javascript/promise
import eyg/runtime/interpreter as r
import harness/stdlib

pub type Interface

@external(javascript, "../plinth_readlines_ffi.js", "createInterface")
pub fn create_interface(
  completer: fn(String) -> #(List(String), String),
) -> Interface

@external(javascript, "../plinth_readlines_ffi.js", "question")
pub fn question(interface: Interface, prompt: String) -> promise.Promise(String)

@external(javascript, "../plinth_readlines_ffi.js", "close")
pub fn close(interface: Interface) -> promise.Promise(String)

pub fn run(source, args) {
  let env = r.Env(scope: [], builtins: stdlib.lib().1)
  let k = Some(r.Kont(r.Apply(r.Defunc(r.Select("exec"), []), [], env), None))
  io.debug("=-====")
  //   r.eval(source, env, None)
  //   |> io.debug
  let rl = create_interface(fn(_) { #([], "") })
  use _ <- promise.await(read(rl))
  close(rl)
  promise.resolve(0)
}

fn read(rl) {
  use answer <- promise.await(question(rl, "> "))
  io.debug(answer)
  case answer == "" {
    True -> promise.resolve(0)
    False -> read(rl)
  }
}
