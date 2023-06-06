import gleam/io
import gleam/list
import gleam/option.{Some}
import eygir/decode
import plinth/browser/window
import plinth/browser/document
import eyg/runtime/interpreter as r
import eyg/analysis/typ as t
import harness/effect
import harness/stdlib
import gleam/javascript/array
import gleam/javascript/promise
import plinth/javascript/promisex
import harness/ffi/cast
import eygir/expression as e

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("Alert", effect.window_alert())
  |> effect.extend("HTTP", effect.http())
  |> effect.extend("Render", render())
  |> effect.extend("Wait", effect.wait())
  |> effect.extend("Async", async())
  |> effect.extend("Listen", listen())
  |> effect.extend("OnClick", on_click())
  |> effect.extend("OnKeyDown", on_keydown())
}

pub fn run() {
  case document.query_selector("script[type=\"application/eygir\"]") {
    Ok(Some(el)) ->
      case decode.from_json(window.decode_uri(document.inner_text(el))) {
        Ok(continuation) ->
          case r.run(continuation, stdlib.env(), r.Record([]), handlers().1) {
            Ok(_) -> Nil
            err -> {
              io.debug(#("return", err))
              Nil
            }
          }
        Error(reason) -> {
          io.debug(reason)
          Nil
        }
      }

    _ -> {
      io.debug("no script to run")

      let elements =
        document.query_selector_all("script[type=\"editor/eygir\"]")
        |> array.to_list()
      list.map(
        elements,
        fn(el) {
          case decode.from_json(window.decode_uri(document.inner_text(el))) {
            Ok(c) -> {
              io.debug(c)
              document.insert_after(el, "<p>Nice</p>")
              Nil
            }
            Error(reason) -> {
              io.debug(reason)
              Nil
            }
          }
        },
      )
      Nil
    }
  }
}

fn render() {
  #(
    t.Binary,
    t.unit,
    fn(page, k) {
      let assert r.Binary(page) = page
      case document.query_selector("#app") {
        Ok(Some(element)) -> document.set_html(element, page)
        _ ->
          panic(
            "could not render as no app element found, the reference to the app element should exist from start time and not be checked on every render",
          )
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
              panic("this shouldn't fail")
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

// different to listen because replaces handler

fn on_click() {
  #(
    t.unit,
    t.unit,
    fn(handle, k) {
      let env = stdlib.env()
      let #(_, extrinsic) = handlers()

      document.on_click(fn(arg) {
        let arg = window.decode_uri(arg)
        let assert Ok(arg) = decode.from_json(arg)

        do_handle(arg, handle, env.builtins, extrinsic)
      })
      r.continue(k, r.unit)
    },
  )
}

fn on_keydown() {
  #(
    t.unit,
    t.unit,
    fn(handle, k) {
      let env = stdlib.env()
      let #(_, extrinsic) = handlers()

      document.on_keydown(fn(k) {
        do_handle(e.Binary(k), handle, env.builtins, extrinsic)
      })
      r.continue(k, r.unit)
    },
  )
}

fn do_handle(arg, handle, builtins, extrinsic) {
  let assert r.Value(arg) = r.eval(arg, stdlib.env(), r.Value)
  // pass as general term to program arg or fn
  let ret =
    r.handle(
      r.eval_call(handle, arg, builtins, r.Value(_)),
      builtins,
      extrinsic,
    )
  case ret {
    r.Value(_) -> Nil
    _ -> {
      io.debug(ret)
      Nil
    }
  }
}
