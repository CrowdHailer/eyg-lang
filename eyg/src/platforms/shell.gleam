import gleam/io
import gleam/map
import gleam/option.{None, Some}
import gleam/javascript/promise
import eyg/runtime/interpreter as r
import harness/stdlib
import plinth/javascript/console
import harness/effect

pub type Interface

@external(javascript, "../plinth_readlines_ffi.js", "createInterface")
pub fn create_interface(
  completer: fn(String) -> #(List(String), String),
) -> Interface

@external(javascript, "../plinth_readlines_ffi.js", "question")
pub fn question(interface: Interface, prompt: String) -> promise.Promise(String)

@external(javascript, "../plinth_readlines_ffi.js", "close")
pub fn close(interface: Interface) -> promise.Promise(String)

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("HTTP", effect.http())
  |> effect.extend("Await", effect.await())
  |> effect.extend("Wait", effect.wait())
  // |> effect.extend("File_Write", file_write())
  // |> effect.extend("Read_Source", read_source())
}

pub fn run(source, args) {
  let env = r.Env(scope: [], builtins: stdlib.lib().1)
  let k_parser =
    Some(r.Kont(r.Apply(r.Defunc(r.Select("lisp"), []), [], env), None))
  let parser = r.handle(r.eval(source, env, k_parser), map.new(), handlers().1)
  io.debug(parser)

  let k =
    Some(r.Kont(
      r.Apply(r.Defunc(r.Select("exec"), []), [], env),
      Some(r.Kont(r.CallWith(r.Record([]), [], env), None)),
    ))
  let r = r.handle(r.eval(source, env, k), map.new(), handlers().1)
  r
  |> console.log
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
