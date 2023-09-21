import gleam/io
import gleam/map
import gleam/option.{None, Some}
import gleam/javascript/promise
import eyg/runtime/interpreter as r
import harness/stdlib
import plinth/javascript/console
import gleam/javascript/array
import eygir/expression as e
import harness/effect
import harness/ffi/core
import harness/impl/http

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
  |> effect.extend("Open", effect.open())
  |> effect.extend("Await", effect.await())
  |> effect.extend("Wait", effect.wait())
  |> effect.extend("Serve", http.serve())
  |> effect.extend("Receive", http.receive())
  // |> effect.extend("File_Write", file_write())
  |> effect.extend("Read_Source", effect.read_source())
  |> effect.extend("LoadDB", effect.load_db())
  |> effect.extend("QueryDB", effect.query_db())
}

pub fn run(source, args) {
  let env = r.Env(scope: [], builtins: stdlib.lib().1)
  let k_parser =
    Some(r.Kont(
      r.Apply(r.Defunc(r.Select("lisp"), []), [], env),
      Some(r.Kont(r.Apply(r.Defunc(r.Select("prompt"), []), [], env), None)),
    ))
  let assert r.Value(parser) =
    r.handle(r.eval(source, env, k_parser), map.new(), handlers().1)
  let parser = fn(raw) {
    let k = Some(r.Kont(r.CallWith(r.Binary(raw), [], env), None))
    let assert r.Value(r.Tagged(tag, value)) =
      r.loop(r.V(r.Value(parser)), [], env, k)
    case tag {
      "Ok" -> r.field(value, "value")
      "Error" -> todo as "error"
    }
  }

  let k =
    Some(r.Kont(
      r.Apply(r.Defunc(r.Select("exec"), []), [], env),
      Some(r.Kont(r.CallWith(r.Record([]), [], env), None)),
    ))
  let assert r.Abort(reason, _rev, env, k) =
    r.handle(r.eval(source, env, k), map.new(), handlers().1)
  // console.log(reason)

  // loop_till
  // needs a different value for handler
  // handler doesn't need builtins
  // Async doesn't rev,e,k if passed in normal stop
  // eval_async pass in handler
  // prompt fn would need to call returned value from prompt effect if using
  // need term-> code

  let rl = create_interface(fn(_) { #([], "") })
  use status <- promise.await(read(rl, parser, env, k))
  close(rl)
  promise.resolve(status)
}

fn read(rl, parser, env, k) {
  use answer <- promise.await(question(rl, "> "))
  let assert Ok(r.LinkedList(cmd)) = parser(answer)
  let assert Ok(code) = core.language_to_expression(cmd)
  case code == e.Empty {
    True -> promise.resolve(0)
    False -> {
      use ret <- promise.await(r.eval_async(code, env, handlers().1))
      let env = case ret {
        Ok(value) -> {
          console.log(r.to_string(value))
          env
        }
        Error(#(r.UnhandledEffect("Prompt", _lift), _rev, env)) -> env
        Error(other) -> {
          console.log(other)
          env
        }
      }
      read(rl, parser, env, k)
    }
  }
}
