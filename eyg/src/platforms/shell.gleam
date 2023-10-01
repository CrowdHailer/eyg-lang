import gleam/io
import gleam/map
import gleam/option.{None, Some}
import gleam/string
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
  |> effect.extend("StopServer", http.stop_server())
  |> effect.extend("Receive", http.receive())
  |> effect.extend("File_Write", effect.file_write())
  |> effect.extend("File_Read", effect.file_read())
  |> effect.extend("Read_Source", effect.read_source())
  |> effect.extend("LoadDB", effect.load_db())
  |> effect.extend("QueryDB", effect.query_db())
  |> effect.extend("Zip", effect.zip())
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
  let parser = fn(prompt) {
    fn(raw) {
      let k =
        Some(r.Kont(
          r.CallWith(r.Binary(prompt), [], env),
          Some(r.Kont(r.CallWith(r.Binary(raw), [], env), None)),
        ))
      let assert r.Value(r.Tagged(tag, value)) =
        r.loop(r.V(r.Value(parser)), [], env, k)
      case tag {
        "Ok" -> r.field(value, "value")
        "Error" -> {
          console.log(value)
          todo as "error"
        }
      }
    }
  }

  let k =
    Some(r.Kont(
      r.Apply(r.Defunc(r.Select("exec"), []), [], env),
      Some(r.Kont(r.CallWith(r.Record([]), [], env), None)),
    ))
  let assert r.Abort(r.UnhandledEffect("Prompt", prompt), _rev, env, k) =
    r.handle(r.eval(source, env, k), map.new(), handlers().1)

  let assert r.Binary(prompt) = prompt

  let rl = create_interface(fn(_) { #([], "") })
  use status <- promise.await(read(rl, parser, env, k, prompt))
  close(rl)
  promise.resolve(status)
}

fn read(rl, parser, env, k, prompt) {
  use answer <- promise.await(question(rl, prompt))
  let assert Ok(r.LinkedList(cmd)) = parser(prompt)(answer)
  let assert Ok(code) = core.language_to_expression(cmd)
  case code == e.Empty {
    True -> promise.resolve(0)
    False -> {
      use ret <- promise.await(r.eval_async(code, env, handlers().1))
      let #(env, prompt) = case ret {
        Ok(value) -> {
          console.log(r.to_string(value))
          #(env, prompt)
        }
        Error(#(r.UnhandledEffect("Prompt", lift), _rev, env)) -> {
          let assert r.Binary(prompt) = lift
          #(env, prompt)
        }
        Error(#(reason, _rev, _env)) -> {
          console.log(string.concat(["!! ", r.reason_to_string(reason)]))
          #(env, prompt)
        }
      }
      read(rl, parser, env, k, prompt)
    }
  }
}
