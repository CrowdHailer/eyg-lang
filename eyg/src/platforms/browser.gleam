import gleam/io
import gleam/option.{Some}
import eygir/decode
import plinth/browser/document
import plinth/browser/console
import eyg/runtime/interpreter as r
import eyg/analysis/typ as t
import harness/effect
import harness/stdlib
import gleam/javascript/promise
import plinth/javascript/promisex

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("Alert", effect.window_alert())
  |> effect.extend("HTTP", effect.http())
  |> effect.extend("Render", render())
  |> effect.extend("Wait", effect.wait())
  |> effect.extend("Async", async())
}

pub fn run() {
  let assert Ok(Some(el)) =
    document.query_selector("script[type=\"application/eygir\"]")
  let assert Ok(continuation) = decode.from_json(document.inner_text(el))

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

fn render() {
  #(
    t.Binary,
    t.unit,
    fn(page, k) {
      let assert r.Binary(page) = page
      case document.query_selector("#app") {
        Ok(Some(element)) -> document.set_text(element, page)
        _ -> todo("error from render")
      }
      r.continue(k, r.unit)
    },
  )
}

fn async() {
  #(
    t.unit,
    t.unit,
    fn(exec, k) {
      let env = stdlib.env()
      let #(_, extrinsic) =
        handlers()
        |> effect.extend("Await", effect.await())
      promisex.wait(0)
      |> promise.map(fn(_: Nil) {
        let ret =
          r.handle(
            r.eval_call(exec, r.unit, env.builtins, r.Value(_)),
            env.builtins,
            extrinsic,
          )
        r.flatten_promise(ret, env, extrinsic)
        |> promise.map(io.debug)
      })
      r.continue(k, r.unit)
    },
  )
}
