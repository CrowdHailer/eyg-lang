import gleam/io
import gleam/option.{Some}
import eygir/decode
import plinth/browser/window
import plinth/browser/document
import plinth/browser/console
import eyg/runtime/interpreter as r
import eyg/analysis/typ as t
import harness/effect
import harness/stdlib
import gleam/javascript/promise
import plinth/javascript/promisex
import harness/ffi/cast

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("Alert", effect.window_alert())
  |> effect.extend("HTTP", effect.http())
  |> effect.extend("Render", render())
  |> effect.extend("Wait", effect.wait())
  |> effect.extend("Async", async())
  |> effect.extend("Listen", listen())
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

pub fn async() {
  #(
    t.unit,
    t.unit,
    fn(exec, k) {
      let env = stdlib.env()
      let #(_, extrinsic) =
        handlers()
        |> effect.extend("Await", effect.await())
      // always needs to be executed later so make wrapped as promise from the start
      let promise =
        promisex.wait(0)
        |> promise.await(fn(_: Nil) {
          let ret =
            r.handle(
              r.eval_call(exec, r.unit, env.builtins, r.Value(_)),
              env.builtins,
              extrinsic,
            )
          r.flatten_promise(ret, env, extrinsic)
        })
        |> promise.map(fn(result) {
          case result {
            Ok(term) -> term
            Error(reason) -> {
              io.debug(reason)
              todo("this shouldn't fail")
            }
          }
        })

      r.continue(k, r.Promise(promise))
    },
  )
}

// maybe on click is a better abstraction
// maybe not as puts more in the platform
// maybe global window or single global ref is a good effect
// Write up how passing the handlers gets to choose run context
// i.e. here the click has async but not await
// single extrinsic for listen is a good idea because internally we can build event handlers for on click etc
// need key value for qwik style continuations on the click
fn listen() {
  #(
    t.unit,
    t.unit,
    fn(sub, k) {
      use event <- cast.field("event", cast.string, sub)
      use handle <- cast.field("handler", cast.any, sub)

      let env = stdlib.env()
      let #(_, extrinsic) = handlers()

      window.add_event_listener(
        event,
        fn(_) {
          let ret =
            r.handle(
              r.eval_call(handle, r.unit, env.builtins, r.Value(_)),
              env.builtins,
              extrinsic,
            )
          io.debug(ret)
          Nil
        },
      )
      r.continue(k, r.unit)
    },
  )
}
