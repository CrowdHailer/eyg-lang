import gleam/io
import gleam/option.{Some}
import eygir/decode
import plinth/browser/document
import plinth/browser/console
import eyg/runtime/interpreter as r
import harness/effect
import harness/stdlib

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("Alert", effect.window_alert())
}

pub fn run() {
  let assert Ok(Some(el)) =
    document.query_selector("script[type=\"application/eygir\"]")
  let assert Ok(continuation) = decode.from_json(document.inner_text(el))

  // let #(_types, values) = stdlib.lib()
  let content = case
    r.run(continuation, stdlib.env(), r.Record([]), handlers().1)
  {
    Ok(r.Binary(content)) -> content
    err -> {
      io.debug(#("return", err))
      "Something went wrong"
    }
  }
  console.log(content)
}
